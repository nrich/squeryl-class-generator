DROP TABLE IF EXISTS example_invoice;
DROP TABLE IF EXISTS example_user;
DROP TABLE IF EXISTS example_user_state_lookup;
DROP TABLE IF EXISTS example_invoice_state_lookup;

CREATE TABLE example_user_state_lookup (
	id integer NOT NULL,
	name varchar(32) NOT NULL,

	PRIMARY KEY(id)
) ENGINE=InnoDB;

CREATE UNIQUE INDEX example_user_state_lookup_name_idx ON example_user_state_lookup(name);

INSERT INTO example_user_state_lookup(id, name) VALUES(1, 'pending');
INSERT INTO example_user_state_lookup(id, name) VALUES(2, 'active');
INSERT INTO example_user_state_lookup(id, name) VALUES(3, 'suspended');
INSERT INTO example_user_state_lookup(id, name) VALUES(4, 'closed');

CREATE TABLE example_invoice_state_lookup (
        id integer NOT NULL,
        state varchar(32) NOT NULL,

        PRIMARY KEY(id)
) ENGINE=InnoDB;

CREATE UNIQUE INDEX example_invoice_state_lookup_name_idx ON example_invoice_state_lookup(state);

INSERT INTO example_invoice_state_lookup(id, state) VALUES(1, 'paid');
INSERT INTO example_invoice_state_lookup(id, state) VALUES(2, 'failed');
INSERT INTO example_invoice_state_lookup(id, state) VALUES(3, 'pending');

CREATE TABLE example_user (
	id integer NOT NULL AUTO_INCREMENT,
	username varchar(254) NOT NULL,
	password varchar(254) NOT NULL,
	email_address varchar(254) NOT NULL,
	created timestamp NOT NULL DEFAULT current_timestamp,
	state integer NOT NULL DEFAULT 1,

	PRIMARY KEY(id),
	FOREIGN KEY(state) REFERENCES example_user_state_lookup(id)
) ENGINE=InnoDB;


CREATE UNIQUE INDEX example_user_username_idx ON example_user(username);
CREATE UNIQUE INDEX example_user_email_idx ON example_user(email_address);

CREATE TABLE example_invoice (
	id integer NOT NULL AUTO_INCREMENT,
	amount double(10,2) NOT NULL,
	user_id integer NOT NULL,
	state integer NOT NULL DEFAULT 3,
	created timestamp NOT NULL DEFAULT current_timestamp,
	processed timestamp NULL,

	PRIMARY KEY(id),
	FOREIGN KEY(user_id) REFERENCES example_user(id),
	FOREIGN KEY(state) REFERENCES example_invoice_state_lookup(id)
) ENGINE=InnoDB;

GRANT ALL ON example.* to 'example'@'localhost' identified by 'example';
