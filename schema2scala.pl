#!/usr/bin/perl 

use strict;
use warnings;

use DBI qw//;
use Data::Dumper qw/Dumper/;
use Getopt::Std qw/getopts/;

my %opts = ();
getopts('hd:u:p:c:S:H:P:', \%opts);
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
import org.squeryl.annotations.{Column, Transient}
import java.util.Date
import java.sql.Timestamp
import org.squeryl.KeyedEntity
import org.squeryl.dsl._

class ${schema_name}Db2ObjectInt extends KeyedEntity[Int] {
\tval id: Int = 0
}

class ${schema_name}Db2ObjectLong extends KeyedEntity[Long] {
\tval id: Long = 0
}


EOF

    for my $table (sort keys %$structure) {
        my $classname = table_to_classname($schema, $table);

        my $values = '';

        if ($table =~ /lookup$/) {
            my @values = ();
            my @prints = ();
            my @ints = ();
            my @strings = ();

            for my $val (@{$structure->{$table}->{enum}}) {
                my ($id, $name) = @$val;
                
                next unless $name;

                my $attrib = ucfirst attribname($name);

                push @values, "\tval $attrib = Value($id, \"$name\")";
                push @prints, "\t\t\tcase $attrib => return \"$name\"";
                push @ints, "\t\t\tcase $id => return $attrib";
                push @strings, "\t\t\tcase \"$name\" => return $attrib";
            } 

            push @prints, "\t\t\tcase _ => throw new IllegalArgumentException";
            push @ints, "\t\t\tcase _ => throw new IllegalArgumentException";
            push @strings, "\t\t\tcase _ => throw new IllegalArgumentException";

            my $values_list = join("\n", @values);
            my $prints_list = join("\n", @prints);
            my $ints_list = join("\n", @ints);
            my $strings_list = join("\n", @strings);

            print <<EOF;
object $classname extends Enumeration {
\ttype $classname = Value
$values_list

\tdef asString(v: $classname): String =
\t\tv match {
$prints_list
\t\t}

\tdef from(v: Int): $classname =
\t\tv match {
$ints_list
\t\t}

\tdef from(v :String): $classname =
\t\tv match {
$strings_list
\t\t}

}
EOF
            next;
        }


        my @cols = ();
        my @defaults = ();
        my @no_default = ();
        my @build_default = ();
        my @no_default_obj = ();
        my @build_default_obj = ();
        my $has_default_obj = 0;
        my $has_full_obj = 0;
        
        my @default_full = ();
        my @build_default_full = ();

        my $idtype = 'Long';

        for my $column (sort keys %{$structure->{$table}->{columns}}) {
            if ($column eq 'id') {
                $idtype = type_lookup($structure->{$table}->{columns}->{$column}->{type});
                next;
            }

            my $attribname = attribname($column);
            my $nullable = uc $structure->{$table}->{columns}->{$column}->{nulls} eq 'YES' ? 1 : 0;
            my $default = $structure->{$table}->{columns}->{$column}->{default};

            my $type = type_lookup($structure->{$table}->{columns}->{$column}->{type}, $nullable);
            my $col_default = type_default($type, $nullable, $default);

            my $refers = $structure->{$table}->{columns}->{$column}->{refers};

            if ($default||$nullable) {
                if ($refers and %$refers and scalar keys %$refers == 1) {
                    my $othertable = (keys %$refers)[0];
                    my $otherattrib = attribname((keys %{$refers->{$othertable}})[0]);
                    my $othertype = table_to_classname($schema, $othertable);

                    (my $paramname = $attribname) =~ s/Id$//;

                    if ($structure->{$othertable}->{enum}) {
                        $type = "$othertype.$othertype";
                        $attribname = $paramname;
                        $col_default = "$othertype.from($default)";

                        push @build_default_full, "$attribname";
                        push @default_full, "$attribname: $type"; 
                    } else {
                        if ($nullable) {
                            push @build_default_full, "$paramname match {case None => None; case Some($paramname) => Some($paramname.$otherattrib) }";
                            push @default_full, "${paramname}: Option[${othertype}]"; 
                        } else {
                            $has_full_obj = 1;
                            push @build_default_full, "$paramname.$otherattrib";
                            push @default_full, "${paramname}: ${othertype}"; 
                        }
                    }
                } else {
                    push @default_full, "${attribname}: ${type}"; 
                    if ($nullable) {
                        push @build_default_full, "$attribname"; 
                    } else {
                        push @build_default_full, $attribname; 
                    }
                }

                push @build_default, $col_default;
                push @build_default_obj, $col_default;
            } else {
                push @no_default, "${attribname}: ${type}";
                push @build_default, $attribname;

                if ($refers and %$refers and scalar keys %$refers == 1) {
                    $has_default_obj = 1;

                    my $othertable = (keys %$refers)[0];
                    my $otherattrib = attribname((keys %{$refers->{$othertable}})[0]);
                    my $othertype = table_to_classname($schema, $othertable);

                    (my $paramname = $attribname) =~ s/Id$//;

                    push @no_default_obj, "${paramname}: ${othertype}";
                    push @build_default_obj, "$paramname.$otherattrib";
                    push @default_full, "${paramname}: ${othertype}"; 
                    push @build_default_full, "$paramname.$otherattrib"; 
                } else {
                    push @no_default_obj, "${attribname}: ${type}";
                    push @build_default_obj, $attribname;
                    push @default_full, "${attribname}: ${type}";
                    push @build_default_full, $attribname; 
                }
            }

            push @defaults, $col_default;

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

                    my $is_unique = 0;

                    my @indexes = keys %{$structure->{$othertable}->{columns}->{$othercol}->{indexes}||{}};

                    if (scalar @indexes == 1 and $structure->{$othertable}->{columns}->{$othercol}->{indexes}->{$indexes[0]}) {
                        $is_unique = 1;
                    }

                    if ($is_unique) {
                        my $optcol = attribname($othercol);

                        if (!$explicit) {
                            $optcol = $othertable;
                            $optcol =~ s/${schema}_//;
                            $optcol = attribname($optcol);
                        }

                        #push @fkeys, "\tlazy val $optcol: Option[$otherclassname] =\n\t\t${schema_name}Schema.${fkey}.left(this).headOption";
                        push @fkeys, "\tlazy val $optcol: $otherclassname =\n\t\t${schema_name}Schema.${fkey}.left(this).single";
                    } else {
                        $plural = attribname($plural);
                        push @fkeys, "\tlazy val $plural: OneToMany[$otherclassname] =\n\t\t${schema_name}Schema.${fkey}.left(this)";
                    }
                }
            } 

            for my $othertable (sort keys %{$refers}) {
                my $otherclassname = table_to_classname($schema, $othertable);
                my $plural = pluralize($othertable);
                $plural =~ s/${schema}_//;

                my $nullable = uc $structure->{$table}->{columns}->{$column}->{nulls} eq 'YES' ? 1 : 0;

                for my $othercol (keys %{$refers->{$othertable}}) {
                    my $fkey = $refers->{$othertable}->{$othercol};

                    my $otherattrib = attribname($column);
                    $otherattrib =~ s/Id$//;

                    if ($structure->{$othertable}->{enum}) {
                        
                    } else {
                        if ($nullable) {
                            push @fkeys, "\t\@Transient\n\tlazy val $otherattrib: Option[$otherclassname] =\n\t\t$attribname match {\n\t\t\tcase Some(x) => ${schema_name}Schema.${fkey}.right(this).headOption\n\t\t\tcase None => None\n\t\t}";
                        } else {
                            push @fkeys, "\tlazy val $otherattrib: $otherclassname =\n\t\t${schema_name}Schema.${fkey}.right(this).single";
                        }
                    }
                }
            } 
        } 

        my $default_list = "\t//No default constructor";
        if (@defaults) {
            $default_list = join(', ', @defaults);
        }

        my $build_default_list = "\t//No simple constructor";
        my $build_default_obj_list = "\t//No simple object constructor";
        my $default_obj_list = "\t//No full object constructor";

        if (scalar @no_default != scalar @build_default) {
            $build_default_list = "\tdef this(" . (join ', ', @no_default) . ") =\n\t\tthis(" . (join ', ', @build_default) . ')';
        }

        if ($has_default_obj) {
            $build_default_obj_list = "\tdef this(" . (join ', ', @no_default_obj) . ") =\n\t\tthis(" . (join ', ', @build_default_obj) . ')';  

            if (scalar @no_default_obj != scalar @default_full) {
                $default_obj_list = "\tdef this(" . (join ', ', @default_full) . ") =\n\t\tthis(" . (join ', ', @build_default_full) . ')';
            }
        } elsif ($has_full_obj) {
            $default_obj_list = "\tdef this(" . (join ', ', @default_full) . ") =\n\t\tthis(" . (join ', ', @build_default_full) . ')';
        }

        my $collist = join (",\n", @cols);

        my $fkeyslist = join ("\n", @fkeys);

        print <<EOF;
class $classname (
$collist
) extends ${schema_name}Db2Object${idtype} {
\tdef this() = 
\t\tthis($default_list)
$build_default_list
$build_default_obj_list
$default_obj_list
$fkeyslist
}

EOF
    }

    print <<EOF;
object ${schema_name}Schema extends Schema {
EOF

    for my $table (sort keys %$structure) {
        next if $structure->{$table}->{enum};

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

                    my $is_unique = $structure->{$table}->{columns}->{$column}->{indexes}->{$index}; 

                    if ($is_unique) {
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
                    next if $structure->{$fkey}->{enum};

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
        if ($type eq 'String') {
            if ($defaultval =~ /^'(.+?)'\:\:character varying/) {
                return "\"$1\"";
            }
        } elsif ($type eq 'Timestamp') {
            if ($defaultval =~ /^'(.+?)'\:\:date/) {
                return "Timestamp.valueOf(\"$1\")";
            }
        }

        return {
            'now()' => 'new Timestamp(System.currentTimeMillis)',
        }->{$defaultval} || $defaultval;
    }

    if ($nullable) {
        return {
#            'Option[Int]' => 'Some(0)',
#            'Option[Long]' => 'Some(0L)',
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

        if ($table =~ /lookup$/ and $column ne 'id') {
            my $rsth = $dbh->prepare("SELECT id, $column FROM $table ORDER BY id"); 
            $rsth->execute();

            my @enum = [];
            while (my ($id, $name) = $rsth->fetchrow_array()) {
                push @enum, [$id, $name];
            }

            $structure->{$table}->{enum} = \@enum;
        }

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
    a.attname as column_name,
    ix.indisunique as is_unique
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

    while (my ($table, $index, $column, $is_unique) = $sth->fetchrow_array()) {
        $structure->{$table}->{columns}->{$column}->{indexes}->{$index} = $is_unique;
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

    (my $classname = $table) =~ s/^${schema}_//;
    $classname =~ s/_lookup$//;
    $classname = join('', map {ucfirst} split '_', lc $classname);

    return $classname;
}

sub pluralize {
    my ($text) = @_;

    $text = $text =~ /s$/ ? "${text}es" : "${text}s";

    $text =~ s/eses$/es/;

    return $text;
}

sub attribname {
    my ($column) = @_;

    return 'id' if $column eq 'id';

    my $attribname = lc $column;
    $attribname =~ s/_id$/Id/g;
    $attribname = lcfirst join '', map {ucfirst $_} split /[\_\-]/, $attribname;

    return $attribname;
}
