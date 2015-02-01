package com.github.nrich

import org.squeryl.PrimitiveTypeMode._
import org.squeryl.Schema
import org.squeryl.annotations.{Column, Transient}
import java.util.Date
import java.sql.Timestamp
import org.squeryl.KeyedEntity
import org.squeryl.dsl._

class ExampleDb2ObjectInt extends KeyedEntity[Int] {
	val id: Int = 0
}

class ExampleDb2ObjectLong extends KeyedEntity[Long] {
	val id: Long = 0
}

class Invoice (
	var amount: BigDecimal,
	var created: Timestamp,
	@Column("payer_id")
	var payerId: Option[Int],
	var processed: Option[Timestamp],
	var state: InvoiceState.InvoiceState,
	@Column("user_id")
	var userId: Int
) extends ExampleDb2ObjectInt {
	def this() = 
		this(0.00, new Timestamp(System.currentTimeMillis), None, None, InvoiceState.from(3), 0)
	def this(amount: BigDecimal, userId: Int) =
		this(amount, new Timestamp(System.currentTimeMillis), None, None, InvoiceState.from(3), userId)
	def this(amount: BigDecimal, user: User) =
		this(amount, new Timestamp(System.currentTimeMillis), None, None, InvoiceState.from(3), user.id)
	def this(amount: BigDecimal, created: Timestamp, payer: Option[User], processed: Option[Timestamp], state: InvoiceState.InvoiceState, user: User) =
		this(amount, created, payer match {case None => None; case Some(payer) => Some(payer.id)}, processed, state, user.id)
	def payment: Option[Payment] =
		ExampleSchema.example_payment_invoice_id_fkey.left(this).headOption
	def payer: Option[User] =
		ExampleSchema.example_invoice_payer_id_fkey.right(this).headOption
	def payer(v: Option[User]): Invoice = {
		 v match {
			case Some(x) => payerId = Some(x.id)
			case None => payerId = None
		}
		return this
	}
	def payer(v: User): Invoice = {
		payerId = Some(v.id)
		return this
	}
	lazy val user: User =
		ExampleSchema.example_invoice_user_id_fkey.right(this).single
	def user(v: User): Invoice = {
		userId = v.id
		return this
	}
}

object InvoiceState extends Enumeration {
	type InvoiceState = Value
	val Paid = Value(1, "paid")
	val Failed = Value(2, "failed")
	val Pending = Value(3, "pending")

	def asString(v: InvoiceState): String =
		v match {
			case Paid => return "paid"
			case Failed => return "failed"
			case Pending => return "pending"
			case _ => throw new IllegalArgumentException
		}

	def from(v: Int): InvoiceState =
		v match {
			case 1 => return Paid
			case 2 => return Failed
			case 3 => return Pending
			case _ => throw new IllegalArgumentException
		}

	def from(v :String): InvoiceState =
		v match {
			case "paid" => return Paid
			case "failed" => return Failed
			case "pending" => return Pending
			case _ => throw new IllegalArgumentException
		}
}

class InvoiceStateLookup (
	var state: String
) extends ExampleDb2ObjectInt {
	def this() = 
		this("")
	//No simple constructor
	//No simple object constructor
	//No full object constructor

}

class Payment (
	var amount: BigDecimal,
	var created: Timestamp,
	@Column("invoice_id")
	var invoiceId: Int
) extends ExampleDb2ObjectInt {
	def this() = 
		this(0.00, new Timestamp(System.currentTimeMillis), 0)
	def this(amount: BigDecimal, invoiceId: Int) =
		this(amount, new Timestamp(System.currentTimeMillis), invoiceId)
	def this(amount: BigDecimal, invoice: Invoice) =
		this(amount, new Timestamp(System.currentTimeMillis), invoice.id)
	def this(amount: BigDecimal, created: Timestamp, invoice: Invoice) =
		this(amount, created, invoice.id)
	lazy val invoice: Invoice =
		ExampleSchema.example_payment_invoice_id_fkey.right(this).single
	def invoice(v: Invoice): Payment = {
		invoiceId = v.id
		return this
	}
}

class User (
	var created: Timestamp,
	@Column("email_address")
	var emailAddress: String,
	var password: String,
	var state: UserState.UserState,
	var username: String
) extends ExampleDb2ObjectInt {
	def this() = 
		this(new Timestamp(System.currentTimeMillis), "", "", UserState.from(1), "")
	def this(emailAddress: String, password: String, username: String) =
		this(new Timestamp(System.currentTimeMillis), emailAddress, password, UserState.from(1), username)
	//No simple object constructor
	//No full object constructor
	lazy val payerInvoices: OneToMany[Invoice] =
		ExampleSchema.example_invoice_payer_id_fkey.left(this)
	lazy val userInvoices: OneToMany[Invoice] =
		ExampleSchema.example_invoice_user_id_fkey.left(this)
}

object UserState extends Enumeration {
	type UserState = Value
	val Pending = Value(1, "pending")
	val Active = Value(2, "active")
	val Suspended = Value(3, "suspended")
	val Closed = Value(4, "closed")

	def asString(v: UserState): String =
		v match {
			case Pending => return "pending"
			case Active => return "active"
			case Suspended => return "suspended"
			case Closed => return "closed"
			case _ => throw new IllegalArgumentException
		}

	def from(v: Int): UserState =
		v match {
			case 1 => return Pending
			case 2 => return Active
			case 3 => return Suspended
			case 4 => return Closed
			case _ => throw new IllegalArgumentException
		}

	def from(v :String): UserState =
		v match {
			case "pending" => return Pending
			case "active" => return Active
			case "suspended" => return Suspended
			case "closed" => return Closed
			case _ => throw new IllegalArgumentException
		}
}

class UserStateLookup (
	var name: String
) extends ExampleDb2ObjectInt {
	def this() = 
		this("")
	//No simple constructor
	//No simple object constructor
	//No full object constructor

}

object ExampleSchema extends Schema {
	val invoices = table[Invoice]("example_invoice")
	on(invoices)(s => declare(
		s.id			is(autoIncremented("example_invoice_id_seq")),
		s.amount		is(dbType("numeric(10,2)")),
		s.created		defaultsTo(new Timestamp(System.currentTimeMillis)),
		s.state		defaultsTo(InvoiceState.from(3))
	))

	val invoice_state_lookups = table[InvoiceStateLookup]("example_invoice_state_lookup")
	on(invoice_state_lookups)(s => declare(
		s.id			is(autoIncremented("example_invoice_state_lookup_id_seq")),
		s.state		is(unique,dbType("character varying(32)"))
	))

	val payments = table[Payment]("example_payment")
	on(payments)(s => declare(
		s.id			is(autoIncremented("example_payment_id_seq")),
		s.amount		is(dbType("numeric(10,2)")),
		s.created		defaultsTo(new Timestamp(System.currentTimeMillis)),
		s.invoiceId		is(unique)
	))

	val users = table[User]("example_user")
	on(users)(s => declare(
		s.id			is(autoIncremented("example_user_id_seq")),
		s.created		defaultsTo(new Timestamp(System.currentTimeMillis)),
		s.emailAddress		is(dbType("text")),
		s.password		is(dbType("character varying(254)")),
		s.state		defaultsTo(UserState.from(1)),
		s.username		is(unique,dbType("character varying(254)"))
	))

	val user_state_lookups = table[UserStateLookup]("example_user_state_lookup")
	on(user_state_lookups)(s => declare(
		s.id			is(autoIncremented("example_user_state_lookup_id_seq")),
		s.name		is(unique,dbType("character varying(32)"))
	))

	val example_invoice_payer_id_fkey = oneToManyRelation(users, invoices).via((a,b) => a.id === b.payerId)
	val example_invoice_user_id_fkey = oneToManyRelation(users, invoices).via((a,b) => a.id === b.userId)
	val example_payment_invoice_id_fkey = oneToManyRelation(invoices, payments).via((a,b) => a.id === b.invoiceId)
}

