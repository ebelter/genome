# This package just defines some classes so you can create plan yaml files that are valid.
package Genome::Annotation::Plan::TestHelpers;

use Sub::Install qw(reinstall_sub);
use Exporter 'import';

our @EXPORT_OK = qw(
    set_what_interpreter_x_requires
);

sub set_what_interpreter_x_requires {
    my @what = @_;
    reinstall_sub( {
        into => 'Genome::Annotation::TestInterpreter',
        as => 'requires_experts',
        code => sub {return @what;},
    });
}

{
    package Genome::Annotation::TestInterpreter;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class Genome::Annotation::TestInterpreter {
        is => 'Genome::Annotation::InterpreterBase',
        has => [
            ix_p1 => {},
            ix_p2 => {},
        ],
    };

    sub name {
        "interpreter_x";
    }

    sub requires_experts {
        return qw(expert_one);
    }

    sub process_entry {
        my $self = shift;
        my $entry = shift;
        my $passed_alleles = shift;
        my %dict;
        for my $allele (@$passed_alleles) {
            my $value = $entry->info("EXP1");
                $dict{$allele} = {
                    exp1 => $value,
                };
        }
        return %dict;
    }

    1;
}

{
    package Genome::Annotation::AnotherTestInterpreter;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class Genome::Annotation::AnotherTestInterpreter {
        is => 'Genome::Annotation::InterpreterBase',
        has => [
            ix_p1 => {},
            ix_p2 => {},
        ],
    };

    sub name {
        "interpreter_y";
    }

    sub process_entry {
        my $self = shift;
        my $entry = shift;
        my $passed_alleles = shift;
        my %dict;
        for my $allele (@$passed_alleles) {
            $dict{$allele} = {
                chrom => $entry->{chrom},
                pos => $entry->{position},
            };
        }
        return %dict;
    }

    1;
}

{
    package Genome::Annotation::TestReporter;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class Genome::Annotation::TestReporter {
        is => 'Genome::Annotation::ReporterBase',
        has => [
            ra_p1 => {},
            ra_p2 => {},
        ],
    };

    sub name {
        "reporter_alpha";
    }

    sub requires_interpreters {
        return qw(interpreter_x);
    }

    sub print_headers {
        my $self = shift;
        $self->_output_fh->print("EXP1\n");
    }

    sub report {
        my $self = shift;
        my $interpretations = shift;
        for my $allele (keys %{$interpretations->{interpreter_x}}) {
            $self->_output_fh->print(_format($interpretations->{interpreter_x}->{$allele}->{exp1})."\n");
        }
    }

    sub _format {
        my $string = shift;
        if (defined $string ) {
            return $string;
        }
        else {
            return "-";
        }
    }

    1;
}

{
    package Genome::Annotation::YetAnotherTestReporter;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class Genome::Annotation::YetAnotherTestReporter {
        is => 'Genome::Annotation::ReporterBase',
        has => [
            rc_p1 => {},
            rc_p2 => {},
        ],

    };

    sub name {
        "reporter_gamma";
    }

    sub requires_interpreters {
        return qw(interpreter_x interpreter_y);
    }

    sub print_headers {
        my $self = shift;
        $self->_output_fh->print("CHROM POS EXP1\n");
    }

    sub report {
        my $self = shift;
        my $interpreters = shift;
        for my $allele (keys %{$interpreters->{interpreter_y}}) {
            my $chrom = _format($interpreters->{interpreter_y}->{$allele}->{chrom});
            my $position = _format($interpreters->{interpreter_y}->{$allele}->{pos});
            my $exp1 = _format($interpreters->{interpreter_x}->{$allele}->{exp1});
            $self->_output_fh->print(join(" ", $chrom, $position, $exp1)."\n");
        }
    }

    sub _format {
        my $string = shift;
        if (defined $string ) {
            return $string;
        }
        else {
            return "*";
        }
    }

    1;
}
{
    package Genome::Annotation::TestAdaptor;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class Genome::Annotation::TestAdaptor {
        is => 'Genome::Annotation::AdaptorBase',
        has_planned_output => [
            e1_p1 => {},
            e1_p2 => {},
        ],
    };
}

{
    package Genome::Annotation::TestExpert;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class Genome::Annotation::TestExpert {
        is => 'Genome::Annotation::ExpertBase',
        has => [
            e1_p1 => {},
            e1_p2 => {},
        ],
    };

    sub name {
        "expert_one";
    }

    sub adaptor_class {
        'Genome::Annotation::TestAdaptor',
    }
}

{
    package Genome::Annotation::AnotherTestExpert;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class Genome::Annotation::AnotherTestExpert {
        is => 'Genome::Annotation::ExpertBase',
        has => [
            e1_p1 => {},
            e1_p2 => {},
        ],
    };

    sub name {
        "expert_two";
    }

    sub adaptor_class {
        'Genome::Annotation::TestAdaptor',
    }

    1;
}

{
    package Genome::Annotation::TestFilter;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class Genome::Annotation::TestFilter {
        is => 'Genome::Annotation::FilterBase',
        has => [
            f1_p1 => {},
            f1_p2 => {},
        ],
    };

    sub name {
        'filter_one';
    }

    sub process_entry {
        my $self = shift;
        my $entry = shift;
        my %returns;
        for my $allele (@{$entry->{alternate_alleles}}) {
            if (length $allele >= $self->f1_p1) {
                $returns{$allele} = 0;
            }
            else {
                $returns{$allele} = 1;
            }
        }
        return %returns;
    }
}

{
    package Genome::Annotation::AnotherTestFilter;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class Genome::Annotation::AnotherTestFilter {
        is => 'Genome::Annotation::FilterBase',
        has => [
            f2_p1 => {},
            f2_p2 => {},
        ],
    };

    sub requires_experts {
        return qw(expert_two);
    }

    sub name {
        'filter_two';
    }

    sub process_entry {
        my $self = shift;
        my $entry = shift;
        return map{$_ => 1} @{$entry->{alternate_alleles}};
    }
}
1;