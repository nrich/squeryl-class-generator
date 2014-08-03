package com.github.nrich;

import org.squeryl.SessionFactory
import org.squeryl.Session
import org.squeryl.adapters.PostgreSqlAdapter
import org.squeryl.PrimitiveTypeMode._

object SchemaExample {
	def main(args: Array[String]) {
		Class.forName("org.postgresql.Driver");

		SessionFactory.concreteFactory = Some(()=>
			Session.create(
			java.sql.DriverManager.getConnection("jdbc:postgresql://localhost:5432/example", "example", "example"),
			new PostgreSqlAdapter))

		transaction {
			import ExampleSchema._

			val user = users.insert(new User("test@test.com", "abc123", "test"))
			user.state = UserState.Active
			users.update(user)

			val invoice = invoices.insert(new Invoice(10.00, user))
		}
	}
}

