#!/usr/bin/perl 

use strict;
use warnings;

use DBI qw//;
use Data::Dumper qw/Dumper/;
use Getopt::Std qw/getopts/;

my %opts = ();
getopts('hd:u:p:s:c:H:P:', \%opts);
main(@ARGV);

sub usage {
    print <<EOF;
Usage: $0 
    [-d dbname]
    [-u username]
    [-p password]
    [-c class package]
    [-H hostname|localhost] 
    [-P port|5432]
    [-S schema prefix|dbname]
EOF

    exit 1;
}

sub main {
    $opts{h} and usage();

    my $dbname = $opts{d} or usage();
    my $username = $opts{u} or usage();
    my $password = $opts{p} or usage();
    my $package = $opts{c} or usage();

    my $host = $opts{H} || 'localhost';
    my $port = $opts{P} || '5432';
    my $schema = $opts{S} || $dbname;

    my $dbh = DBI->connect(
        "DBI:Pg:dbname=$dbname;host=$host;port=$port",
        $username,
        $password,
        {   
                AutoCommit => 0,
                RaiseError => 1
        }
    );

    # generate table structure
    my $structure = generate_structure($dbh, $schema);

    for my $table (keys %$structure) {
        generate_index($dbh, $structure, $table); 
        generate_fkeys($dbh, $structure, $table); 
    }

    #print STDERR Dumper $structure;
    output_file($schema, $structure, $package);

    $dbh->rollback();
}

sub output_file {
    my ($schema, $structure, $package) = @_;

    my $schema_name = ucfirst lc $schema;

    print <<EOF;
package $package

import org.squeryl.PrimitiveTypeMode._
import org.squeryl.Schema
import org.squeryl.annotations.Column
import java.util.Date
import java.sql.Timestamp
import org.squeryl.KeyedEntity
import org.squeryl.dsl._

class ${schema_name}Db2Object extends KeyedEntity[Long] {
\tval id: Long = 0
}

EOF

    for my $table (sort keys %$structure) {
        my $classname = table_to_classname($schema, $table);

        my @cols = ();
        my @defaults = ();
        my @no_default = ();
        my @build_default = ();
        for my $column (sort keys %{$structure->{$table}->{columns}}) {
            next if $column eq 'id';

            my $attribname = attribname($column);
            my $nullable = uc $structure->{$table}->{columns}->{$column}->{nulls} eq 'YES' ? 1 : 0;
            my $default = $structure->{$table}->{columns}->{$column}->{default};

            my $type = type_lookup($structure->{$table}->{columns}->{$column}->{type}, $nullable);
            my $col_default = type_default($type, $nullable, $default);
            push @defaults, $col_default;

            if ($default||$nullable) {
                push @build_default, $col_default;
            } else {
                push @no_default, "${attribname}: ${type}";
                push @build_default, $attribname;
            }

            my $col = '';

            if ($attribname ne $column) {
                $col .= "\t\@Column(\"$column\")\n";
            }

            $col .= "\tvar $attribname: $type";

            push @cols, $col;
        } 

        my @fkeys = ();
        for my $column (sort keys %{$structure->{$table}->{columns}}) {
            my $attribname = attribname($column);

            my $nullable = uc $structure->{$table}->{columns}->{$column}->{nulls} eq 'YES' ? 1 : 0;

            my $referred = $structure->{$table}->{columns}->{$column}->{referred};
            my $refers = $structure->{$table}->{columns}->{$column}->{refers};

            for my $othertable (keys %{$referred}) {
                my $otherclassname = table_to_classname($schema, $othertable);
                my $plural = pluralize($othertable);
                $plural =~ s/${schema}_//;

                my $explicit = keys %{$referred->{$othertable}} > 1 ? 1 : 0;

                for my $othercol (keys %{$referred->{$othertable}}) {
                    my $fkey = $referred->{$othertable}->{$othercol};

                    if ($explicit) {
                        my $otherattrib = attribname($othercol);
                        $plural = pluralize($otherattrib);
                    }

                    push @fkeys, "\tlazy val $plural: OneToMany[$otherclassname] = ${schema_name}Schema.${fkey}.left(this)";
                }
            } 

            for my $othertable (sort keys %{$refers}) {
                my $otherclassname = table_to_classname($schema, $othertable);
                my $plural = pluralize($othertable);
                $plural =~ s/${schema}_//;

                for my $othercol (keys %{$refers->{$othertable}}) {
                    my $fkey = $refers->{$othertable}->{$othercol};

                    my $otherattrib = attribname($column);
                    $otherattrib =~ s/ID$//;

                    push @fkeys, "\tlazy val $otherattrib: $otherclassname = ${schema_name}Schema.${fkey}.right(this).single";
                }
            } 
        } 

        my $default_list = '';
        if (@defaults) {
            $default_list = join(', ', @defaults);
        }

        my $build_default_list = '';
        if (@no_default) {
            $build_default_list = "\tdef this(" . (join ', ', @no_default) . ') = this(' . (join ', ', @build_default) . ')';
        }

        my $collist = join (",\n", @cols);

        my $fkeyslist = join ("\n", @fkeys);

        print <<EOF;
class $classname ( 
$collist
) extends ${schema_name}Db2Object {
\tdef this() = this($default_list)
$build_default_list
$fkeyslist
}

EOF
    }

    print <<EOF;
object ${schema_name}Schema extends Schema {
EOF

    for my $table (sort keys %$structure) {
        (my $varname = $table) =~ s/${schema}_//;
        $varname = lc $varname;

        my $classname = table_to_classname($schema, $table);
        $varname = pluralize($varname);
        
        print <<EOF;
\tval $varname = table[$classname]("$table")
EOF

        my @declarations = ();

        for my $column (sort keys %{$structure->{$table}->{columns}}) {
            if ($column eq 'id') {
                unshift @declarations, "\t\ts.id\t\t\tis(autoIncremented(\"${table}_id_seq\"))";
                next;
            }

            my @attribs = ();

            my $indexes = $structure->{$table}->{columns}->{$column}->{indexes};

            if ($indexes and %$indexes) {
                for my $index (sort {length $a <=> length $b} keys %$indexes) {
                    next if $index =~ /_like$/;

                    if ($index =~ /uniq/) {
                        unshift @attribs, 'unique';
                    } else {
                        push @attribs, "indexed(\"$index\")";
                    }
                }
            }

            if (@attribs) {
                my $attriblist = join(',', @attribs);

                my $attribname = attribname($column);
                
                push @declarations, "\t\ts.$attribname\t\tis($attriblist)";
            }
        }

        if (@declarations) {
            my $declaration_list = join(",\n", @declarations);

            print <<EOF;
\ton($varname)(s => declare(
$declaration_list
\t))

EOF
        }
    }

    for my $table (keys %$structure) {
        (my $varname = $table) =~ s/${schema}_//;
        $varname = lc $varname;

        my $plural = pluralize($varname);

        for my $column (keys %{$structure->{$table}->{columns}}) {
            my $fkeys = $structure->{$table}->{columns}->{$column}->{refers};

            next unless $fkeys and %$fkeys;

            for my $fkey (keys %$fkeys) {
                (my $other = $fkey) =~ s/${schema}_//;
                $other = lc $other;

                $other = pluralize($other);

                for my $othercol (keys %{$fkeys->{$fkey}}) {
                    my $nullable = uc $structure->{$fkey}->{columns}->{$othercol}->{nulls} eq 'YES' ? 1 : 0;
                    next if $nullable;

                    my $fkey_name = $fkeys->{$fkey}->{$othercol};

                    my $attribname = attribname($column);

                    print <<EOF;
\tval $fkey_name = oneToManyRelation($other, $plural).via((a,b) => a.$othercol === b.$attribname)
EOF
                }
            }
        }
    }

    print <<EOF;
}

EOF
}

sub type_lookup {
    my ($type, $nullable) = @_;

    my $newtype = {
        'character varying' => 'String',
        'integer' => 'Int',
        'bigint' => 'Long',
        'boolean' => 'Boolean',
        'date' => 'Timestamp',
        'text' => 'String',
        'timestamp with time zone' => 'Timestamp',
        'timestamp without time zone' => 'Timestamp',
        'smallint' => 'Int',
        'numeric' => 'BigDecimal',
    }->{$type}||die "Unknown type `$type'\n";

    if ($nullable) {
        $newtype = "Option[$newtype]";
    }

    return $newtype;
}

sub type_default {
    my ($type, $nullable, $defaultval) = @_;

    if ($defaultval) {
        return {
            'now()' => 'new Timestamp(System.currentTimeMillis)',
        }->{$defaultval} || $defaultval;
    }

    if ($nullable) {
        return {
            'Option[Int]' => 'Some(0)',
        }->{$type} || 'None';
    }

    my $default = {
        'String' => '""',
        'Int' => '0',
        'Long' => '0',
        'Boolean' => 'false',
        'Timestamp' => 'new Timestamp(0L)',
        'Short' => '0',
        'BigDecimal' => '0.00',
    }->{$type};

    die "Unknown type `$type'\n" unless defined $default;

    return $default;
}


sub generate_structure {
    my ($dbh, $schema) = @_;

    my $column_query =<<EOF;
select column_name, data_type,table_name,character_maximum_length,is_nullable,column_default
from information_schema.columns 
where (table_name like '${schema}_%' or table_name = 'auth_user')
EOF

    my $sth = $dbh->prepare($column_query);
    $sth->execute();

    my $structure = {};
    while (my ($column, $datatype, $table, $maxlen, $nullable, $default) = $sth->fetchrow_array()) {
        $default ||= '';
        $default = $default =~ /^nextval/ ? undef : $default;

        $structure->{$table}->{columns}->{$column} = {
            type => $datatype,
            max => $maxlen,
            nulls => $nullable,
            default => $default,
        };
    }

    $sth->finish();

    return $structure;
}

sub generate_index {
    my ($dbh, $structure, $tablename) = @_;

    my $index_query =<<EOF;
select
    t.relname as table_name,
    i.relname as index_name,
    a.attname as column_name
from
    pg_class t,
    pg_class i,
    pg_index ix,
    pg_attribute a
where
    t.oid = ix.indrelid
    and i.oid = ix.indexrelid
    and a.attrelid = t.oid
    and a.attnum = ANY(ix.indkey)
    and t.relkind = 'r'
    and t.relname=?
EOF

    my $sth = $dbh->prepare($index_query);
    $sth->execute($tablename);

    while (my ($table, $index, $column) = $sth->fetchrow_array()) {
        $structure->{$table}->{columns}->{$column}->{indexes}->{$index} = 1;
    }

    return $structure;
}

sub generate_fkeys {
    my ($dbh, $structure, $tablename) = @_;

    my $fkey_query =<<EOF;
SELECT 
    tc.constraint_name, tc.table_name, kcu.column_name, 
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name 
FROM 
    information_schema.table_constraints AS tc 
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
WHERE constraint_type = 'FOREIGN KEY' and tc.table_name=?
EOF

    my $sth = $dbh->prepare($fkey_query);
    $sth->execute($tablename);

    while (my ($name, $table, $column, $ftable, $fcolumn) = $sth->fetchrow_array()) {
        $structure->{$table}->{columns}->{$column}->{refers}->{$ftable}->{$fcolumn} = $name;
        $structure->{$ftable}->{columns}->{$fcolumn}->{referred}->{$table}->{$column} = $name;
    }

    return $structure;
}

sub table_to_classname {
    my ($schema, $table) = @_;

    (my $classname = $table) =~ s/${schema}_//;
    $classname = join('', map {ucfirst} split '_', lc $classname);

    return $classname;
}

sub pluralize {
    my ($text) = @_;

    $text = $text =~ /s$/ ? "${text}es" : "${text}s";

    $text =~ s/eses/es/;

    return $text;
}

sub attribname {
    my ($column) = @_;

    return 'id' if $column eq 'id';

    my $attribname = lc $column;
    $attribname =~ s/id$/ID/g;
    $attribname = lcfirst join '', map {ucfirst $_} split /[\_\-]/, $attribname;

    return $attribname;
}
