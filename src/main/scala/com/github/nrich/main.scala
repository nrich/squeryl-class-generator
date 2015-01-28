package com.github.nrich;

import org.squeryl.SessionFactory
import org.squeryl.Session
import org.squeryl.adapters.{PostgreSqlAdapter,H2Adapter,MySQLAdapter}
import org.squeryl.PrimitiveTypeMode._

object SchemaExample {
	def main(args: Array[String]) {
                var dbtype = "mysql";

                if (args.length > 0) {
                    dbtype = args(0);
                }

                if (dbtype == "postgres") {
		    Class.forName("org.postgresql.Driver")

		    SessionFactory.concreteFactory = Some(()=>
			Session.create(
			java.sql.DriverManager.getConnection("jdbc:postgresql://localhost:5432/example", "example", "example"),
			new PostgreSqlAdapter))
                } else if (dbtype == "sqlite") {
                    Class.forName("org.sqlite.JDBC")
                    
                    SessionFactory.concreteFactory = Some(()=>
                            Session.create(
                            java.sql.DriverManager.getConnection("jdbc:sqlite:/tmp/example.db"), 
                            new H2Adapter))
                } else if (dbtype == "mysql") {
                    Class.forName("com.mysql.jdbc.Driver")
                    
                    SessionFactory.concreteFactory = Some(()=>
                            Session.create(
                            java.sql.DriverManager.getConnection("jdbc:mysql://localhost:3306/example", "example", "example"), 
                            new MySQLAdapter))
                } else {
                    throw new IllegalArgumentException("Unknown database type")
                }

		transaction {
			import ExampleSchema._

			val user = users.insert(new User("test@test.com", "abc123", "test"))
			user.state = UserState.Active
			users.update(user)

			val invoice = invoices.insert(new Invoice(10.00, user))
		}
	}
}

