package com.github.nrich

import org.squeryl.PrimitiveTypeMode._
import org.squeryl.Schema
import org.squeryl.annotations.{Column, Transient}
import java.sql.Date
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
	var note: Option[String],
	@Column("payer_id")
	var payerId: Option[Int],
	var processed: Option[Timestamp],
	var refund: Option[BigDecimal],
	var state: InvoiceState.Enum,
	@Column("user_id")
	var userId: Int
) extends ExampleDb2ObjectInt {
	def this() =
		this(BigDecimal(0.0), new Timestamp(System.currentTimeMillis), None, None, None, None, InvoiceState.from(3), 0)
	def this(amount: BigDecimal, userId: Int) =
		this(amount, new Timestamp(System.currentTimeMillis), None, None, None, None, InvoiceState.from(3), userId)
	def this(amount: BigDecimal, user: User) =
		this(amount, new Timestamp(System.currentTimeMillis), None, None, None, None, InvoiceState.from(3), user.id)
	def this(amount: BigDecimal, created: Timestamp, note: Option[String], payer: Option[User], processed: Option[Timestamp], refund: Option[BigDecimal], state: InvoiceState.Enum, user: User) =
		this(amount, created, note, payer match {case None => None; case Some(payer) => Some(payer.id)}, processed, refund, state, user.id)
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
	assume(amount <= 999.99 && amount >= -999.99, "amount must be between -999.99 and 999.99 inclusive")
	note match {case Some(note) => assume(note.length <= 254, "note must be at most 254 characters"); case None => {}}
	refund match {case Some(refund) => assume(refund <= 999.99 && refund >= -999.99, "refund must be between -999.99 and 999.99 inclusive"); case None => {}}
}

object InvoiceState extends Enumeration {
	type Enum = Value
	val Paid = Value(1, "paid")
	val Failed = Value(2, "failed")
	val Pending = Value(3, "pending")

	def asString(v: Enum): String =
		v match {
			case Paid => return "paid"
			case Failed => return "failed"
			case Pending => return "pending"
			case _ => throw new IllegalArgumentException
		}

	def asInt(v: Enum): Int =
		v match {
			case Paid => return 1
			case Failed => return 2
			case Pending => return 3
			case _ => throw new IllegalArgumentException
		}


	def from(v: Int): Enum =
		v match {
			case 1 => return Paid
			case 2 => return Failed
			case 3 => return Pending
			case _ => throw new IllegalArgumentException
		}

	def from(v: String): Enum =
		v.toLowerCase match {
			case "paid" => return Paid
			case "failed" => return Failed
			case "pending" => return Pending
			case _ => throw new IllegalArgumentException
		}
}

class InvoiceStateLookup (
	var state: String
) extends ExampleDb2ObjectInt {
	private def this() =
		this("")
	//No simple constructor
	//No simple object constructor
	//No full object constructor
	//No foreign keys
	//No assumptions
}

class Payment (
	var amount: BigDecimal,
	var created: Timestamp,
	@Column("invoice_id")
	var invoiceId: Int,
	var ref: String,
	@Column("type_id")
	var typeval: PaymentType.Enum
) extends ExampleDb2ObjectInt {
	def this() =
		this(BigDecimal(0.0), new Timestamp(System.currentTimeMillis), 0, "", PaymentType.from(1))
	def this(amount: BigDecimal, invoiceId: Int, ref: String, typeval: PaymentType.Enum) =
		this(amount, new Timestamp(System.currentTimeMillis), invoiceId, ref, typeval)
	def this(amount: BigDecimal, invoice: Invoice, ref: String, typeval: PaymentType.Enum) =
		this(amount, new Timestamp(System.currentTimeMillis), invoice.id, ref, typeval)
	def this(amount: BigDecimal, created: Timestamp, invoice: Invoice, ref: String, typeval: PaymentType.Enum) =
		this(amount, created, invoice.id, ref, typeval)
	lazy val invoice: Invoice =
		ExampleSchema.example_payment_invoice_id_fkey.right(this).single
	def invoice(v: Invoice): Payment = {
		invoiceId = v.id
		return this
	}
	assume(amount <= 999.99 && amount >= -999.99, "amount must be between -999.99 and 999.99 inclusive")
	assume(ref.length <= 32, "ref must be at most 32 characters")
}

object PaymentType extends Enumeration {
	type Enum = Value
	val CreditCard = Value(1, "credit card")
	val DirectDebit = Value(2, "direct debit")
	val Cash = Value(3, "cash")

	def asString(v: Enum): String =
		v match {
			case CreditCard => return "credit card"
			case DirectDebit => return "direct debit"
			case Cash => return "cash"
			case _ => throw new IllegalArgumentException
		}

	def asInt(v: Enum): Int =
		v match {
			case CreditCard => return 1
			case DirectDebit => return 2
			case Cash => return 3
			case _ => throw new IllegalArgumentException
		}


	def from(v: Int): Enum =
		v match {
			case 1 => return CreditCard
			case 2 => return DirectDebit
			case 3 => return Cash
			case _ => throw new IllegalArgumentException
		}

	def from(v: String): Enum =
		v.toLowerCase match {
			case "credit card" => return CreditCard
			case "direct debit" => return DirectDebit
			case "cash" => return Cash
			case _ => throw new IllegalArgumentException
		}
}

class PaymentTypeLookup (
	var name: String
) extends ExampleDb2ObjectInt {
	private def this() =
		this("")
	//No simple constructor
	//No simple object constructor
	//No full object constructor
	//No foreign keys
	//No assumptions
}

class Signup (
	var created: Timestamp,
	var token: String,
	@Column("user_id")
	var userId: Int
) extends ExampleDb2ObjectInt {
	def this() =
		this(new Timestamp(System.currentTimeMillis), "", 0)
	def this(token: String, userId: Int) =
		this(new Timestamp(System.currentTimeMillis), token, userId)
	def this(token: String, user: User) =
		this(new Timestamp(System.currentTimeMillis), token, user.id)
	def this(created: Timestamp, token: String, user: User) =
		this(created, token, user.id)
	lazy val user: User =
		ExampleSchema.example_signup_user_id_fkey.right(this).single
	def user(v: User): Signup = {
		userId = v.id
		return this
	}
	assume(token.length <= 32, "token must be at most 32 characters")
}

class User (
	var created: Timestamp,
	@Column("email_address")
	var emailAddress: String,
	var password: String,
	var state: UserState.Enum,
	var username: String
) extends ExampleDb2ObjectInt {
	def this() =
		this(new Timestamp(System.currentTimeMillis), "", "", UserState.from(0), "")
	def this(emailAddress: String, password: String, username: String) =
		this(new Timestamp(System.currentTimeMillis), emailAddress, password, UserState.from(0), username)
	//No simple object constructor
	//No full object constructor
	lazy val payerInvoices: OneToMany[Invoice] =
		ExampleSchema.example_invoice_payer_id_fkey.left(this)
	lazy val userInvoices: OneToMany[Invoice] =
		ExampleSchema.example_invoice_user_id_fkey.left(this)
	def signup: Option[Signup] =
		ExampleSchema.example_signup_user_id_fkey.left(this).headOption
	assume(password.length <= 254, "password must be at most 254 characters")
	assume(username.length <= 254, "username must be at most 254 characters")
}

object UserState extends Enumeration {
	type Enum = Value
	val Pending = Value(0, "pending")
	val Active = Value(1, "active")
	val Suspended = Value(2, "suspended")
	val Closed = Value(3, "closed")

	def asString(v: Enum): String =
		v match {
			case Pending => return "pending"
			case Active => return "active"
			case Suspended => return "suspended"
			case Closed => return "closed"
			case _ => throw new IllegalArgumentException
		}

	def asInt(v: Enum): Int =
		v match {
			case Pending => return 0
			case Active => return 1
			case Suspended => return 2
			case Closed => return 3
			case _ => throw new IllegalArgumentException
		}


	def from(v: Int): Enum =
		v match {
			case 0 => return Pending
			case 1 => return Active
			case 2 => return Suspended
			case 3 => return Closed
			case _ => throw new IllegalArgumentException
		}

	def from(v: String): Enum =
		v.toLowerCase match {
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
	private def this() =
		this("")
	//No simple constructor
	//No simple object constructor
	//No full object constructor
	//No foreign keys
	//No assumptions
}

object ExampleSchema extends Schema {
	val invoices = table[Invoice]("example_invoice")
	on(invoices)(s => declare(
		s.id			is(autoIncremented("example_invoice_id_seq")),
		s.amount		is(dbType("numeric(5,2)")),
		s.created		defaultsTo(new Timestamp(System.currentTimeMillis)),
		s.note		is(dbType("character varying(254)")),
		s.refund		is(dbType("numeric(5,2)")),
		s.state		defaultsTo(InvoiceState.from(3))
	))

	val invoice_state_lookups = table[InvoiceStateLookup]("example_invoice_state_lookup")
	on(invoice_state_lookups)(s => declare(
		s.id			is(autoIncremented("example_invoice_state_lookup_id_seq")),
		s.state		is(unique,indexed("example_invoice_state_lookup_name_idx"),dbType("character varying(32)"))
	))

	val payments = table[Payment]("example_payment")
	on(payments)(s => declare(
		s.id			is(autoIncremented("example_payment_id_seq")),
		s.amount		is(dbType("numeric(5,2)")),
		s.created		defaultsTo(new Timestamp(System.currentTimeMillis)),
		s.invoiceId		is(unique,indexed("example_payment_user_id_idx")),
		s.ref		is(dbType("character varying(32)")),
		columns(s.ref,s.typeval)		are(unique, indexed("example_payment_type_id_ref_idx"))
	))

	val payment_type_lookups = table[PaymentTypeLookup]("example_payment_type_lookup")
	on(payment_type_lookups)(s => declare(
		s.id			is(autoIncremented("example_payment_type_lookup_id_seq")),
		s.name		is(unique,indexed("example_payment_type_lookup_name_idx"),dbType("character varying(32)"))
	))

	val signups = table[Signup]("example_signup")
	on(signups)(s => declare(
		s.id			is(autoIncremented("example_signup_id_seq")),
		s.created		defaultsTo(new Timestamp(System.currentTimeMillis)),
		s.token		is(dbType("character varying(32)")),
		s.userId		is(unique,indexed("example_signup_user_id_idx")),
		columns(s.token,s.userId)		are(unique, indexed("example_signup_user_id_token_idx"))
	))

	val users = table[User]("example_user")
	on(users)(s => declare(
		s.id			is(autoIncremented("example_user_id_seq")),
		s.created		defaultsTo(new Timestamp(System.currentTimeMillis)),
		s.emailAddress		is(dbType("text")),
		s.password		is(dbType("character varying(254)")),
		s.state		defaultsTo(UserState.from(0)),
		s.username		is(unique,indexed("example_user_username_idx"),dbType("character varying(254)"))
	))

	val user_state_lookups = table[UserStateLookup]("example_user_state_lookup")
	on(user_state_lookups)(s => declare(
		s.id			is(autoIncremented("example_user_state_lookup_id_seq")),
		s.name		is(unique,indexed("example_user_state_lookup_name_idx"),dbType("character varying(32)"))
	))

	val example_invoice_payer_id_fkey = oneToManyRelation(users, invoices).via((a,b) => a.id === b.payerId)
	val example_invoice_user_id_fkey = oneToManyRelation(users, invoices).via((a,b) => a.id === b.userId)
	val example_payment_invoice_id_fkey = oneToManyRelation(invoices, payments).via((a,b) => a.id === b.invoiceId)
	val example_signup_user_id_fkey = oneToManyRelation(users, signups).via((a,b) => a.id === b.userId)
}

