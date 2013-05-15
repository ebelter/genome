use warnings;
use strict;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above 'Genome';
use Test::More;

my $cls = "Genome::Model::DifferentialExpression::Command::GMTCuffdiffWrapper";
use_ok($cls, "can use");

# stub out the function for testing to just touch a file.
my $_exe_fn = $cls . "::_execute_gmt_cuffdiff";
no strict "refs";
*$_exe_fn = sub {
    my $self = shift;
    my $output_directory = shift;

    my $new_file = "$output_directory/" . $self->transcript_gtf_file;
    diag "Touching $new_file\n";
    `touch $new_file`;
    return 1;
};
use strict;

my $temp_dir = Genome::Sys->create_temp_directory();
diag "Created Temporary Directory at: $temp_dir\n";

my $cmd = $cls->execute(
    transcript_gtf_file => 'some_file',
    bam_file_paths => 'some_files',
    output_directory => $temp_dir,
    cuffdiff_params => 'some_params',
);

is($cmd->result->class, $cls . "::Result", "Result is of proper auto-generated class");

my $result = $cmd->result;
diag "SoftwareResult output_dir: " . $result->output_dir . "\n";
my $some_file = $cmd->result->output_dir . "/some_file";
ok(-e $some_file, 'SoftwareResult has data produced from command execution');


my $same_cmd = $cls->execute(
    transcript_gtf_file => 'some_file',
    bam_file_paths => 'some_files',
    output_directory => $temp_dir,
    cuffdiff_params => 'some_params',
);
is($same_cmd->result->id, $cmd->result->id, "Same result for same inputs");

my $different_cmd = $cls->execute(
    transcript_gtf_file => 'some_different_file',
    bam_file_paths => 'some_files',
    output_directory => $temp_dir,
    cuffdiff_params => 'some_params',
);
isnt($different_cmd->result->id, $cmd->result->id, "Different result for different inputs");

done_testing();

1;
