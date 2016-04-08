#!/usr/bin/perl 

use strict;
use warnings;

use DBI qw//;
use Data::Dumper qw/Dumper/;
use Getopt::Std qw/getopts/;

my %opts = ();
getopts('hd:u:p:c:S:H:P:T:', \%opts);
main(@ARGV);

sub usage {
    print <<EOF;
Usage: $0 
    [-d dbname]
    [-u username]
    [-p password]
    [-c class package]
    [-H hostname|localhost] 
    [-P port|5432|3306]
    [-S schema prefix|dbname] - require for Sqlite
    [-T database type|Postgres]
EOF

    exit 1;
}

sub main {
    $opts{h} and usage();

    my $type = lc ($opts{T} || 'postgres');

    my $dbname = $opts{d} or usage();
    my $package = $opts{c} or usage();
    my $host = $opts{H} || 'localhost';
    my $schema = $opts{S};

    my $schemaObj = undef;
    if ($type eq 'postgres') {
        my $username = $opts{u} or usage();
        my $password = $opts{p} or usage();
        my $port = $opts{P} || '5432';

        $schema ||= $dbname;

        my $dbh = DBI->connect(
            "DBI:Pg:dbname=$dbname;host=$host;port=$port",
            $username,
            $password,
            {
                AutoCommit => 0,
                RaiseError => 1
            }
        );
        
        $schemaObj = PostgresSchema->new($dbh);
    } elsif ($type eq 'mysql') {
        my $username = $opts{u} or usage();
        my $password = $opts{p} or usage();
        my $port = $opts{P} || '3306';

        $schema ||= $dbname;

        my $dbh = DBI->connect(
            "DBI:mysql:dbname=$dbname;host=$host;port=$port",
            $username,
            $password,
            {
                AutoCommit => 0,
                RaiseError => 1
            }
        );
        
        $schemaObj = MysqlSchema->new($dbh);
    } elsif ($type eq 'sqlite') {
        $schema or usage();

        my $dbh = DBI->connect(
            "DBI:SQLite:dbname=$dbname",
            undef,
            undef,
            {
                AutoCommit => 0,
                RaiseError => 1
            }
        );

        $schemaObj = SqliteSchema->new($dbh);
    } else {
        die "Unknown database type `$type'\n";
    }

    # generate table structure
    my $structure = $schemaObj->generateSchemaData($schema);

    #print STDERR Dumper $structure;
    output_file($schema, $structure, $package);

}

sub output_file {
    my ($schema, $structure, $package) = @_;

    my $schema_name = ucfirst lc $schema;

    print <<EOF;
package $package

import org.squeryl.PrimitiveTypeMode._
import org.squeryl.Schema
import org.squeryl.annotations.{Column, Transient}
import java.sql.Date
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
            my @iprints = ();
            my @ints = ();
            my @strings = ();

            for my $val (@{$structure->{$table}->{enum}}) {
                my ($id, $name) = @$val;

                my $lcname = lc $name;
                
                my $attrib = uc $name eq $name ? uc attribname($name) : ucfirst attribname($name);

                push @values, "\tval $attrib = Value($id, \"$name\")";
                push @prints, "\t\t\tcase $attrib => return \"$name\"";
                push @iprints, "\t\t\tcase $attrib => return $id";
                push @ints, "\t\t\tcase $id => return $attrib";
                push @strings, "\t\t\tcase \"$lcname\" => return $attrib";
            } 

            push @prints, "\t\t\tcase _ => throw new IllegalArgumentException";
            push @iprints, "\t\t\tcase _ => throw new IllegalArgumentException";
            push @ints, "\t\t\tcase _ => throw new IllegalArgumentException";
            push @strings, "\t\t\tcase _ => throw new IllegalArgumentException";

            my $values_list = join("\n", @values);
            my $prints_list = join("\n", @prints);
            my $iprints_list = join("\n", @iprints);
            my $ints_list = join("\n", @ints);
            my $strings_list = join("\n", @strings);

            print <<EOF;
object $classname extends Enumeration {
\ttype Enum = Value
$values_list

\tdef asString(v: Enum): String =
\t\tv match {
$prints_list
\t\t}

\tdef asInt(v: Enum): Int =
\t\tv match {
$iprints_list
\t\t}


\tdef from(v: Int): Enum =
\t\tv match {
$ints_list
\t\t}

\tdef from(v: String): Enum =
\t\tv.toLowerCase match {
$strings_list
\t\t}
}

EOF
            $classname .= "Lookup";
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

        my @assumptions = ();

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

            if (defined $default||$nullable) {
                if ($refers and %$refers and scalar keys %$refers == 1) {
                    my $othertable = (keys %$refers)[0];
                    my $otherattrib = attribname((keys %{$refers->{$othertable}})[0]);
                    my $othertype = table_to_classname($schema, $othertable);

                    (my $paramname = $attribname) =~ s/Id$//;

                    $paramname = reserved_name($paramname) || $paramname;

                    if ($structure->{$othertable}->{enum}) {
                        $type = "$othertype.Enum";
                        $attribname = $paramname;
                        $col_default = "$othertype.from($default)";

                        $structure->{$table}->{columns}->{$column}->{defaultval} = $col_default;
                        $structure->{$table}->{columns}->{$column}->{enum} = 1;

                        push @build_default_full, "$attribname";
                        push @default_full, "$attribname: $type"; 
                    } else {
                        if ($nullable) {
                            push @build_default_full, "$paramname match {case None => None; case Some($paramname) => Some($paramname.$otherattrib)}";
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
                if ($refers and %$refers and scalar keys %$refers == 1) {
                    my $othertable = (keys %$refers)[0];
                    my $otherattrib = attribname((keys %{$refers->{$othertable}})[0]);
                    my $othertype = table_to_classname($schema, $othertable);

                    (my $paramname = $attribname) =~ s/Id$//;

                    $paramname = reserved_name($paramname) || $paramname;

                    if ($structure->{$othertable}->{enum}) {
                        $type = "$othertype.Enum";
                        $attribname = $paramname;

                        my $defval = $structure->{$othertable}->{enum}->[0]->[0];
                        $col_default = "$othertype.from($defval)";

                        $structure->{$table}->{columns}->{$column}->{enum} = 1;

                        push @no_default, "${paramname}: ${type}";
                        push @build_default, $attribname;
                       
                        push @no_default_obj, "${paramname}: ${type}";
                        push @build_default_obj, "$attribname";

                        push @default_full, "$attribname: $type";
                        push @build_default_full, "$attribname";
                    } else {
                        $has_default_obj = 1;
                        push @no_default, "${attribname}: ${type}";
                        push @build_default, $attribname;

                        push @no_default_obj, "${paramname}: ${othertype}";
                        push @build_default_obj, "$paramname.$otherattrib";
                        push @default_full, "${paramname}: ${othertype}"; 
                        push @build_default_full, "$paramname.$otherattrib"; 
                    }
                } else {
                    push @no_default, "${attribname}: ${type}";
                    push @build_default, $attribname;

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

            if (my $len = $structure->{$table}->{columns}->{$column}->{length}) {
                if ($type eq 'String') {
                    push @assumptions, "\tassume($attribname.length <= $len, \"$attribname must be at most $len characters\")";
                } elsif ($type eq 'BigDecimal') {
                    my ($l, $r) = split ',', $len;

                    $r ||= 0;
                    $l -= $r;

                    my $max = $r ? sprintf '%d.%d', 9 x $l, 9 x $r : 9 x $l;

                    push @assumptions, "\tassume($attribname <= $max && $attribname >= -$max, \"$attribname must be between -$max and $max inclusive\")";
                }
            }

            push @cols, $col;
        } 

        my @fkeys = ();
        for my $column (sort keys %{$structure->{$table}->{columns}}) {
            my $attribname = attribname($column);

            my $nullable = uc $structure->{$table}->{columns}->{$column}->{nulls} eq 'YES' ? 1 : 0;

            my $referred = $structure->{$table}->{columns}->{$column}->{referred};
            my $refers = $structure->{$table}->{columns}->{$column}->{refers};

            for my $othertable (sort keys %{$referred}) {
                my $otherclassname = table_to_classname($schema, $othertable);
                my $plural = pluralize($othertable);
                $plural =~ s/${schema}_//;

                my $explicit = keys %{$referred->{$othertable}} > 1 ? 1 : 0;

                for my $othercol (sort keys %{$referred->{$othertable}}) {
                    my $fkey = $referred->{$othertable}->{$othercol};

                    if ($explicit) {
                        my $otherattrib = attribname($othercol);
                        $otherattrib =~ s/Id$//;
                        $plural = pluralize(attribname("${otherattrib}_${otherclassname}"));
                    } else {
                        $plural = attribname($plural);
                    }

                    my $is_unique = 0;

                    my @indexes = keys %{$structure->{$othertable}->{columns}->{$othercol}->{indexes}||{}};

                    for my $index (sort @indexes) {
                        next unless $structure->{$othertable}->{columns}->{$othercol}->{indexes}->{$index};

                        $is_unique = 1;
                        for my $col (grep {$_ ne $othercol} sort keys %{$structure->{$othertable}->{columns}}) {
                            if ($structure->{$othertable}->{columns}->{$col}->{indexes}->{$index}) {
                                $is_unique = 0;
                            }
                        }

                        last if $is_unique;
                    }

                    if ($is_unique) {
                        my $optcol = attribname($othercol);
                        if (!$explicit) {
                            $optcol = $othertable;
                            $optcol =~ s/${schema}_//;
                            $optcol = attribname($optcol);
                        }

                        push @fkeys, "\tdef $optcol: Option[$otherclassname] =\n\t\t${schema_name}Schema.${fkey}.left(this).headOption";
                    } else {
                        push @fkeys, "\tlazy val $plural: OneToMany[$otherclassname] =\n\t\t${schema_name}Schema.${fkey}.left(this)";
                    }
                }
            } 

            for my $othertable (sort keys %{$refers}) {
                my $otherclassname = table_to_classname($schema, $othertable);
                my $plural = pluralize($othertable);
                $plural =~ s/${schema}_//;

                my $nullable = uc $structure->{$table}->{columns}->{$column}->{nulls} eq 'YES' ? 1 : 0;

                for my $othercol (sort keys %{$refers->{$othertable}}) {
                    my $fkey = $refers->{$othertable}->{$othercol};

                    my $otherattrib = attribname($column);
                    $otherattrib =~ s/Id$//;

                    my $oa = attribname($othercol);

                    if ($structure->{$othertable}->{enum}) {
                        
                    } else {
                        if ($nullable) {
                            push @fkeys, "\tdef $otherattrib: Option[$otherclassname] =\n\t\t${schema_name}Schema.${fkey}.right(this).headOption";
                            push @fkeys, "\tdef $otherattrib(v: Option[$otherclassname]): $classname = {\n\t\t v match {\n\t\t\tcase Some(x) => $attribname = Some(x.$oa)\n\t\t\tcase None => $attribname = None\n\t\t}\n\t\treturn this\n\t}";
                            push @fkeys, "\tdef $otherattrib(v: $otherclassname): $classname = {\n\t\t$attribname = Some(v.$oa)\n\t\treturn this\n\t}";
                        } else {
                            push @fkeys, "\tlazy val $otherattrib: $otherclassname =\n\t\t${schema_name}Schema.${fkey}.right(this).single";
                            push @fkeys, "\tdef $otherattrib(v: $otherclassname): $classname = {\n\t\t$attribname = v.$oa\n\t\treturn this\n\t}";
                        }
                    }
                }
            } 
        } 

        if ($structure->{$table}->{enum}) {
            @fkeys = ();
            @assumptions = ();
        }

        my $default_list = "\t//No default constructor";
        if (@defaults) {
            $default_list = join(', ', @defaults);
        }

        my $build_default_list = "\t//No simple constructor";
        my $build_default_obj_list = "\t//No simple object constructor";
        my $default_obj_list = "\t//No full object constructor";

	my $classdef = $classname =~ /Lookup$/ ? 'private def' : 'def';

        if (scalar @no_default != scalar @build_default) {
            $build_default_list = "\t$classdef this(" . (join ', ', @no_default) . ") =\n\t\tthis(" . (join ', ', @build_default) . ')';
        }

        if ($has_default_obj) {
            $build_default_obj_list = "\t$classdef this(" . (join ', ', @no_default_obj) . ") =\n\t\tthis(" . (join ', ', @build_default_obj) . ')';  

            if (scalar @no_default_obj != scalar @default_full) {
                $default_obj_list = "\t$classdef this(" . (join ', ', @default_full) . ") =\n\t\tthis(" . (join ', ', @build_default_full) . ')';
            }
        } elsif ($has_full_obj) {
            $default_obj_list = "\t$classdef this(" . (join ', ', @default_full) . ") =\n\t\tthis(" . (join ', ', @build_default_full) . ')';
        }

        my $assumptionslist = join "\n", @assumptions;
        $assumptionslist ||= "\t//No assumptions";

        my $collist = join ",\n", @cols;

        my $fkeyslist = join "\n", @fkeys;
        $fkeyslist ||= "\t//No foreign keys";

        print <<EOF;
class $classname (
$collist
) extends ${schema_name}Db2Object${idtype} {
\t$classdef this() =
\t\tthis($default_list)
$build_default_list
$build_default_obj_list
$default_obj_list
$fkeyslist
$assumptionslist
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
        $classname .= "Lookup" if $structure->{$table}->{enum};
        $varname = pluralize($varname);
        
        print <<EOF;
\tval $varname = table[$classname]("$table")
EOF

        my @declarations = ();

        my $multi_unique = {};
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
                        for my $col (grep {$_ ne $column} sort keys %{$structure->{$table}->{columns}}) {
                            if ($structure->{$table}->{columns}->{$col}->{indexes}->{$index}) {
                                $multi_unique->{$index}->{$col} = 1;
                            }
                        }

                        unless (defined $multi_unique->{$index}) {
                            unshift @attribs, "indexed(\"$index\")";
                            unshift @attribs, 'unique';
                        }
                    } else {
                        push @attribs, "indexed(\"$index\")";
                    }
                }
            }

            my $type = $structure->{$table}->{columns}->{$column}->{type}; 
            my $len = $structure->{$table}->{columns}->{$column}->{length}; 

            if ($len) {
                push @attribs, "dbType(\"$type($len)\")";
            } elsif ($type eq 'text') {
                push @attribs, "dbType(\"text\")";
            }

            if (my $default = $structure->{$table}->{columns}->{$column}->{defaultval}) {
                my $attribname = attribname($column);
                $attribname =~ s/Id$//;
                $attribname = reserved_name($attribname) || $attribname;

                push @declarations, "\t\ts.$attribname\t\tdefaultsTo($default)";
            } elsif ($default = $structure->{$table}->{columns}->{$column}->{default}) {
                $default = type_default(type_lookup($structure->{$table}->{columns}->{$column}->{type}), 0, $default);

                my $attribname = attribname($column);
                push @declarations, "\t\ts.$attribname\t\tdefaultsTo($default)";
            }

            if (@attribs) {
                my $attriblist = join(',', @attribs);

                my $attribname = attribname($column);
                
                push @declarations, "\t\ts.$attribname\t\tis($attriblist)";
            }
        }

        for my $index (sort keys %$multi_unique) {
            my @columns = ();

            for my $col (sort keys %{$multi_unique->{$index}}) {
                my $attribname = attribname($col);

                if ($structure->{$table}->{columns}->{$col}->{enum}) {
                    $attribname =~ s/Id$//;
                }

                $attribname = reserved_name($attribname) || $attribname;
                push @columns, "s.$attribname";
            }

            my $columns = join ',', @columns;
            push @declarations, "\t\tcolumns($columns)\t\tare(unique, indexed(\"$index\"))";
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

    for my $table (sort keys %$structure) {
        (my $varname = $table) =~ s/${schema}_//;
        $varname = lc $varname;

        my $plural = pluralize($varname);

        for my $column (sort keys %{$structure->{$table}->{columns}}) {
            my $fkeys = $structure->{$table}->{columns}->{$column}->{refers};

            next unless $fkeys and %$fkeys;

            for my $fkey (sort keys %$fkeys) {
                (my $other = $fkey) =~ s/${schema}_//;
                $other = lc $other;

                $other = pluralize($other);

                for my $othercol (sort keys %{$fkeys->{$fkey}}) {
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
        'varchar' => 'String',
        'integer' => 'Int',
        'int' => 'Int',
        'bigint' => 'Long',
        'boolean' => 'Boolean',
        'date' => 'Date',
        'text' => 'String',
        'datetime' => 'Timestamp',
        'timestamp' => 'Timestamp',
        'timestamp with time zone' => 'Timestamp',
        'timestamp without time zone' => 'Timestamp',
        'smallint' => 'Int',
        'numeric' => 'BigDecimal',
        'decimal' => 'BigDecimal',
        'double' => 'double',
        'double precision' => 'double',
        'float' => 'float',
        'real' => 'float',
        'geometry' => 'String',
    }->{lc $type}||die "Unknown type `$type'\n";

    if ($nullable) {
        $newtype = "Option[$newtype]";
    }

    return $newtype;
}

sub type_default {
    my ($type, $nullable, $defaultval) = @_;

    return undef unless $type;

    if ($defaultval) {
        if ($type eq 'String') {
            if ($defaultval =~ /^'(.*?)'\:\:character varying/) {
                return "\"$1\"";
            }
        } elsif ($type eq 'Timestamp') {
            if ($defaultval =~ /^'(.+?)'\:\:date/) {
                return "Timestamp.valueOf(\"$1\")";
            } elsif ($defaultval =~ /^'(.+?)'\:\:timestamp/) {
                return "Timestamp.valueOf(\"$1\")";
            } elsif ($defaultval =~ /^'(.+?)'/) {
                return "Timestamp.valueOf(\"$1\")";
            }
        } elsif ($type eq 'Date') {
            if ($defaultval =~ /^'(.+?)'\:\:date/) {
                return "Date.valueOf(\"$1\")";
            } elsif ($defaultval =~ /^'(.+?)'/) {
                return "Date.valueOf(\"$1\")";
            }

        } elsif ($type eq 'BigDecimal') {
	    return "BigDecimal($defaultval)";
        }

        return {
            'now()' => 'new Timestamp(System.currentTimeMillis)',
            'current_timestamp' => 'new Timestamp(System.currentTimeMillis)',
            'CURRENT_TIMESTAMP' => 'new Timestamp(System.currentTimeMillis)',
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
        'Long' => '0L',
        'Boolean' => 'false',
        'Timestamp' => 'new Timestamp(0L)',
        'Date' => 'new Date(0L)',
        'Short' => '0',
        'BigDecimal' => 'BigDecimal(0.0)',
        'double' => '0.0',
        'float' => '0.0',
    }->{$type};

    die "Unknown type `$type'\n" unless defined $default;

    return $default;
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

    $text = $text =~ /sh?$/ ? "${text}es" : "${text}s";
    $text =~ s/eses$/es/;
    $text =~ s/ys$/ies/;

    return $text;
}

sub reserved_name {
    my ($name) = @_;

    return {
        type => 'typeval',
        private => 'privateval',
        package => 'packageval',
    }->{lc $name};
}

sub attribname {
    my ($column) = @_;

    return 'id' if $column eq 'id';

    # reserved word check
    my $reservedmangle = reserved_name($column);
    return $reservedmangle if $reservedmangle;

    my $attribname = lc $column;
    $attribname =~ s/_id$/Id/g;
    $attribname = lcfirst join '', map {ucfirst $_} split /[\_\-\s]/, $attribname;

    return $attribname;
}


package BaseSchema;

sub new {
    my ($classname, $dbh) = @_;

    return bless {
        dbh => $dbh,
    }, $classname;
}

sub DESTROY {
    my ($self) = @_;

    $self->{dbh}->rollback();
}

1;

package SqliteSchema;
use base 'BaseSchema';

sub generateSchemaData {
    my ($self, $schema) = @_;

    my $dbh = $self->{dbh};

    my @tables = ();

    my $structure = {};

    my $sth = $dbh->prepare('SELECT name FROM sqlite_master WHERE type=?');
    $sth->execute('table');

    while (my ($name) = $sth->fetchrow_array()) {
        push @tables, $name;
    }

    for my $table (sort @tables) {
        my $tableinfo = $dbh->prepare("PRAGMA table_info($table)");
        $tableinfo->execute();

        while (my (undef, $column, $datatype, $notnullable, $default) = $tableinfo->fetchrow_array()) {
            my $len = undef;

            if ($datatype =~ /^(.+?)\((.+?)\)$/) {
                $datatype = $1;
                $len = $2; 
            }

            if ($table =~ /lookup$/ and $column ne 'id') {
                my $rsth = $dbh->prepare("SELECT id, $column FROM $table ORDER BY id"); 
                $rsth->execute();

                my @enum = ();
                while (my ($id, $name) = $rsth->fetchrow_array()) {
                    push @enum, [$id, $name];
                }

                $structure->{$table}->{enum} = \@enum;
            }

            $default = defined $default && $default =~ /^nextval/ ? undef : $default;

            $structure->{$table}->{columns}->{$column} = {
                type => $datatype,
                length => $len,
                nulls => $notnullable ? 'NO' : 'YES',
                default => $default,
            };
        }
    }

    for my $table (sort @tables) {
        my $fkeylist = $dbh->prepare("PRAGMA foreign_key_list($table)");
        $fkeylist->execute();

        while (my (undef, undef, $ftable, $column, $fcolumn) = $fkeylist->fetchrow_array()) {
            my $name = "${table}_${column}_fkey";

            $structure->{$table}->{columns}->{$column}->{refers}->{$ftable}->{$fcolumn} = $name;
            $structure->{$ftable}->{columns}->{$fcolumn}->{referred}->{$table}->{$column} = $name;
        }

        my $indexlist = $dbh->prepare("PRAGMA index_list($table)");
        $indexlist->execute();

        while (my (undef, $index, $is_unique) = $indexlist->fetchrow_array()) {
            my $indexinfo = $dbh->prepare("PRAGMA index_info($index)");
            $indexinfo->execute();

            while (my (undef, undef, $column) = $indexinfo->fetchrow_array()) {
                $structure->{$table}->{columns}->{$column}->{indexes}->{$index} = $is_unique;
            }
        }
    }

    return $structure;
}

1;

package PostgresSchema;
use base 'BaseSchema';

sub generateSchemaData {
    my ($self, $schema) = @_;

    my $structure = $self->_generateStructure($schema);

    for my $table (sort keys %$structure) {
        $self->_generateIndex($structure, $table); 
        $self->_generateFkeys($structure, $table); 
    }

    return $structure;
}

sub _generateStructure {
    my ($self, $schema) = @_;

    my $dbh = $self->{dbh};

    my $column_query =<<EOF;
select column_name, data_type,table_name,character_maximum_length,is_nullable,column_default,numeric_precision,numeric_scale,udt_name
from information_schema.columns 
where (table_name like '${schema}_%' or table_name = 'auth_user')
EOF

    my $sth = $dbh->prepare($column_query);
    $sth->execute();

    my $structure = {};
    while (my ($column, $datatype, $table, $len, $nullable, $default, $numeric_precision_radix, $numeric_scale, $udt_name) = $sth->fetchrow_array()) {

        if ($table =~ /lookup$/ and $column ne 'id') {
            my $rsth = $dbh->prepare("SELECT id, $column FROM $table ORDER BY id"); 
            $rsth->execute();

            my @enum = ();
            while (my ($id, $name) = $rsth->fetchrow_array()) {
                push @enum, [$id, $name];
            }

            $structure->{$table}->{enum} = \@enum;
        }

        $default = defined $default && $default =~ /^nextval/ ? undef : $default;

        if ($numeric_scale) {
            $len = "$numeric_precision_radix,$numeric_scale";
        }

        $structure->{$table}->{columns}->{$column} = {
            type => $datatype eq 'USER-DEFINED' ? $udt_name : $datatype,
            length => $len,
            nulls => $nullable,
            default => $default,
        };
    }

    $sth->finish();

    return $structure;
}

sub _generateIndex {
    my ($self, $structure, $tablename) = @_;

    my $dbh = $self->{dbh};

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

sub _generateFkeys {
    my ($self, $structure, $tablename) = @_;

    my $dbh = $self->{dbh};

    my $fkey_query =<<EOF;
SELECT 
    tc.table_name, kcu.column_name, 
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

    while (my ($table, $column, $ftable, $fcolumn) = $sth->fetchrow_array()) {
        my $name = "${table}_${column}_fkey";
        $structure->{$table}->{columns}->{$column}->{refers}->{$ftable}->{$fcolumn} = $name;
        $structure->{$ftable}->{columns}->{$fcolumn}->{referred}->{$table}->{$column} = $name;
    }

    return $structure;
}

1;

package MysqlSchema;
use base 'BaseSchema';

sub generateSchemaData {
    my ($self, $schema) = @_;

    my $dbh = $self->{dbh};

    my @tables = ();

    my $structure = {};

    my $sth = $dbh->prepare('SHOW TABLES');
    $sth->execute();

    while (my ($name) = $sth->fetchrow_array()) {
        push @tables, $name;
    }

    for my $table (sort @tables) {
        my $tableinfo = $dbh->prepare("SHOW COLUMNS FROM $table");
        $tableinfo->execute();

        while (my ($column, $datatype, $nullable, undef, $default) = $tableinfo->fetchrow_array()) {
            my $len = undef;

            if ($datatype eq 'int(11)') {
                $datatype = 'integer';
            } elsif ($datatype =~ /^(.+?)\((.+?)\)$/) {
                $datatype = $1;
                $len = $2; 
            }

            if ($table =~ /lookup$/ and $column ne 'id') {
                my $rsth = $dbh->prepare("SELECT id, $column FROM $table ORDER BY id"); 
                $rsth->execute();

                my @enum = ();
                while (my ($id, $name) = $rsth->fetchrow_array()) {
                    push @enum, [$id, $name];
                }

                $structure->{$table}->{enum} = \@enum;
            }

            $default = defined $default && $default =~ /^nextval/ ? undef : $default;

            $structure->{$table}->{columns}->{$column} = {
                type => $datatype,
                length => $len,
                nulls => $nullable,
                default => $default,
            };
        }
    }

    for my $table (sort @tables) {
        my $fkey_query =<<EOF;
SELECT
    column_name,referenced_table_name,referenced_column_name
FROM
    information_schema.key_column_usage
WHERE
    referenced_table_name IS NOT NULL
    AND table_schema = ?     
    AND table_name = ?
EOF

        my $fkeylist = $dbh->prepare($fkey_query);
        $fkeylist->execute($schema, $table);

        while (my ($column, $ftable, $fcolumn) = $fkeylist->fetchrow_array()) {
            my $name = "${table}_${column}_fkey";

            $structure->{$table}->{columns}->{$column}->{refers}->{$ftable}->{$fcolumn} = $name;
            $structure->{$ftable}->{columns}->{$fcolumn}->{referred}->{$table}->{$column} = $name;
        }

        my $index_query =<<EOF;
SELECT
    column_name,index_name,non_unique 
FROM
    information_schema.statistics
WHERE
    table_schema = ?     
    AND table_name = ?
    AND column_name != 'PRIMARY'
    AND column_name != index_name
EOF

        my $indexlist = $dbh->prepare($index_query);
        $indexlist->execute($schema, $table);

        while (my ($column, $index, $not_unique) = $indexlist->fetchrow_array()) {
            $structure->{$table}->{columns}->{$column}->{indexes}->{$index} = $not_unique ? 0 : 1;
        }
    }

    return $structure;
}

1;

