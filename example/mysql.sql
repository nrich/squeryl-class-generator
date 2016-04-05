DROP TABLE IF EXISTS example_payment;
DROP TABLE IF EXISTS example_invoice;
DROP TABLE IF EXISTS example_signup;
DROP TABLE IF EXISTS example_user;
DROP TABLE IF EXISTS example_user_state_lookup;
DROP TABLE IF EXISTS example_invoice_state_lookup;
DROP TABLE IF EXISTS example_payment_type_lookup;

CREATE TABLE example_user_state_lookup (
	id integer NOT NULL UNIQUE,
	name varchar(32) NOT NULL
) ENGINE=InnoDB;

CREATE UNIQUE INDEX example_user_state_lookup_name_idx ON example_user_state_lookup(name);

INSERT INTO example_user_state_lookup(id, name) VALUES(0, 'pending');
INSERT INTO example_user_state_lookup(id, name) VALUES(1, 'active');
INSERT INTO example_user_state_lookup(id, name) VALUES(2, 'suspended');
INSERT INTO example_user_state_lookup(id, name) VALUES(3, 'closed');

CREATE TABLE example_invoice_state_lookup (
	id integer NOT NULL UNIQUE,
        state varchar(32) NOT NULL
) ENGINE=InnoDB;

CREATE UNIQUE INDEX example_invoice_state_lookup_name_idx ON example_invoice_state_lookup(state);

INSERT INTO example_invoice_state_lookup(id, state) VALUES(1, 'paid');
INSERT INTO example_invoice_state_lookup(id, state) VALUES(2, 'failed');
INSERT INTO example_invoice_state_lookup(id, state) VALUES(3, 'pending');

CREATE TABLE example_payment_type_lookup (
        id integer NOT NULL UNIQUE,
        name varchar(32) NOT NULL
);

CREATE UNIQUE INDEX example_payment_type_lookup_name_idx ON example_payment_type_lookup(name);

INSERT INTO example_payment_type_lookup(id, name) VALUES(1, 'credit card');
INSERT INTO example_payment_type_lookup(id, name) VALUES(2, 'direct debit');
INSERT INTO example_payment_type_lookup(id, name) VALUES(3, 'cash');

CREATE TABLE example_user (
	id integer PRIMARY KEY NOT NULL AUTO_INCREMENT,
	username varchar(254) NOT NULL,
	password varchar(254) NOT NULL,
	email_address text NOT NULL,
	created timestamp NOT NULL DEFAULT current_timestamp,
	state integer NOT NULL DEFAULT 0,

	FOREIGN KEY(state) REFERENCES example_user_state_lookup(id)
) ENGINE=InnoDB;

CREATE UNIQUE INDEX example_user_username_idx ON example_user(username);

CREATE TABLE example_signup (
        id integer PRIMARY KEY NOT NULL AUTO_INCREMENT,
        user_id integer NOT NULL,
        created timestamp NOT NULL DEFAULT current_timestamp,
        token varchar(32) NOT NULL,

        FOREIGN KEY(user_id) REFERENCES example_user(id)
);

CREATE UNIQUE INDEX example_signup_user_id_token_idx ON example_signup(user_id, token);

CREATE TABLE example_invoice (
	id integer PRIMARY KEY NOT NULL AUTO_INCREMENT,
        amount decimal(10,2) NOT NULL,
	user_id integer NOT NULL,
	payer_id integer NULL,
	state integer NOT NULL DEFAULT 3,
	created timestamp NOT NULL DEFAULT current_timestamp,
	processed timestamp NULL,

	FOREIGN KEY(user_id) REFERENCES example_user(id),
	FOREIGN KEY(payer_id) REFERENCES example_user(id),
	FOREIGN KEY(state) REFERENCES example_invoice_state_lookup(id)
) ENGINE=InnoDB;

CREATE TABLE example_payment (
        id integer PRIMARY KEY NOT NULL AUTO_INCREMENT,
        amount decimal(10,2) NOT NULL,
	invoice_id integer NOT NULL,
        created timestamp NOT NULL DEFAULT current_timestamp,
        type_id integer NOT NULL,
        ref varchar(32) NOT NULL,

        FOREIGN KEY(invoice_id) REFERENCES example_invoice(id),
        FOREIGN KEY(type_id) REFERENCES example_payment_type_lookup(id)
) ENGINE=InnoDB;

CREATE UNIQUE INDEX example_payment_user_id_idx ON example_payment(invoice_id);
CREATE UNIQUE INDEX example_payment_type_id_ref_idx ON example_payment(type_id, ref);

GRANT ALL ON example.* to 'example'@'localhost' identified by 'example';
