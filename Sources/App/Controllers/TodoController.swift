import Vapor
import FluentSQLite
import Crypto

struct TodoController: RouteCollection {

	func boot(router: Router) throws {
		let todosRoute = router.grouped("todos")

		let tokenAuthMiddleware = User.tokenAuthMiddleware()
		let guardAuthMiddleware = User.guardAuthMiddleware()
		let tokenAuthGroup = todosRoute.grouped(tokenAuthMiddleware, guardAuthMiddleware)

		tokenAuthGroup.post(use: createHandler)
		tokenAuthGroup.get(Todo.parameter, use: getHandler)
		tokenAuthGroup.get(use: getAllHandler)
		tokenAuthGroup.put(Todo.parameter, use: updateHandler)
		tokenAuthGroup.delete(Todo.parameter, use: deleteHandler)
	}

}

// MARK: - Handlers
private extension TodoController {

	func getHandler(_ req: Request) throws -> Future<Todo.Public> {
		let user = try req.requireAuthenticated(User.self)
		guard let todoId = req.parameters.values.compactMap({ Int($0.value) }).first else {
			throw Abort(.badRequest)
		}

		return try user.children.query(on: req).filter(\.id == todoId).first().map(to: Todo.self) { possibleTodo in
			guard let todo = possibleTodo else {
				throw Abort(.notFound)
			}
			return todo
		}.public
	}

	func getAllHandler(_ req: Request) throws -> Future<[Todo.Public]> {
		let user = try req.requireAuthenticated(User.self)
		return try user.children.query(on: req).all().map(to: [Todo.Public].self) { todos in
			return todos.map { $0.public }
		}
	}

	func createHandler(_ req: Request) throws -> Future<Todo.Public> {
		let user = try req.requireAuthenticated(User.self)
		return try req.content.decode(Todo.CreateRequest.self).flatMap { todo in
			let todo = try Todo(title: todo.title, userId: user.requireID())
			try todo.validate()
			return todo.save(on: req).public
		}
	}

	func updateHandler(_ req: Request) throws -> Future<Todo.Public> {
		return try flatMap(to: Todo.Public.self, req.parameters.next(Todo.self), req.content.decode(Todo.CreateRequest.self)) { todo, updateData in
			todo.title = updateData.title
			try todo.validate()
			return todo.save(on: req).public
		}
	}

	func deleteHandler(_ req: Request) throws -> Future<HTTPStatus> {
		let user = try req.requireAuthenticated(User.self)

		return try req.parameters.next(Todo.self).flatMap { todo -> Future<Void> in
			guard try todo.userId == user.requireID() else {
				throw Abort(.forbidden)
			}
			return todo.delete(on: req)
		}.transform(to: .ok)
	}
	
}
