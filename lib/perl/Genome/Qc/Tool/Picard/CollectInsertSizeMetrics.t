#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Sub::Override;
use Genome::Test::Factory::InstrumentData::Solexa;
use Genome::Test::Factory::InstrumentData::AlignmentResult;
use Cwd qw(abs_path);


my $pkg = 'Genome::Qc::Tool::Picard::CollectInsertSizeMetrics';
use_ok($pkg);

my $data_dir = __FILE__.".d";

use Genome::Qc::Tool;
my $sample_name_override = Sub::Override->new(
    'Genome::Qc::Tool::sample_name',
    sub { return 'TEST-patient1-somval_tumor1'; },
);

my $instrument_data = Genome::Test::Factory::InstrumentData::Solexa->setup_object(
    flow_cell_id => '12345ABXX',
    lane => '2',
    subset_name => '2',
    run_name => 'example',
    id => 'NA12878',
);
my $alignment_result = Genome::Test::Factory::InstrumentData::AlignmentResult->setup_object(
    instrument_data => $instrument_data,
);

my $bam_file = abs_path(File::Spec->join($data_dir, 'speedseq_merged.bam'));
my $temp_directory = Genome::Sys->create_temp_file_path;
my $temp_file = Genome::Sys->create_temp_file_path;

use Genome::Qc::Config;
my $config_override = Sub::Override->new(
    'Genome::Qc::Config::get_commands_for_alignment_result',
    sub {
        return {
            picard_collect_insert_size_metrics => {
                class => 'Genome::Qc::Tool::Picard::CollectInsertSizeMetrics',
                params => {
                    input_file => $bam_file,
                    use_version => 1.123,
                    metric_accumulation_level => ['SAMPLE'],
                    temp_directory => $temp_directory,
                    histogram_file => $temp_file,
                }
            },
        },
    },
);

my $command = Genome::Qc::Run->create(
    config_name => 'testing-qc-run',
    alignment_result => $alignment_result,
    %{Genome::Test::Factory::SoftwareResult::User->setup_user_hash},
);
ok($command->execute, "Command executes ok");

my %tools = $command->output_result->_tools;
my ($tool) = values %tools;
ok($tool->isa($pkg), 'Tool created successfully');

my $output = $tool->qc_metrics_file;
my @expected_cmd_line = (
    'java',
    '-Xmx4096m',
    '-XX:MaxPermSize=64m',
    '-cp',
    '/usr/share/java/ant.jar:/gscmnt/sata132/techd/solexa/jwalker/lib/picard-tools-1.123/CollectInsertSizeMetrics.jar',
    'picard.analysis.CollectInsertSizeMetrics',
    sprintf('HISTOGRAM_FILE=%s', $temp_file),
    sprintf('INPUT=%s', $bam_file),
    'MAX_RECORDS_IN_RAM=500000',
    'METRIC_ACCUMULATION_LEVEL=SAMPLE',
    sprintf('OUTPUT=%s', $output),
    sprintf('TMP_DIR=%s', $temp_directory),
    'VALIDATION_STRINGENCY=SILENT',
);
is_deeply([$tool->cmd_line], [@expected_cmd_line], 'Command line list as expected');

my %expected_metrics = (
    'FR-MAX_INSERT_SIZE' => 244,
    'FR-MEAN_INSERT_SIZE' => 187,
    'FR-MEDIAN_ABSOLUTE_DEVIATION' => 20.5,
    'FR-MEDIAN_INSERT_SIZE' => 183.5,
    'FR-MIN_INSERT_SIZE' => 138,
    'FR-READ_PAIRS' => 14,
    'FR-SAMPLE' => 'TEST-patient1-somval_tumor1',
    'FR-STANDARD_DEVIATION' => 32.597782,
    'FR-WIDTH_OF_10_PERCENT' => 3,
    'FR-WIDTH_OF_20_PERCENT' => 19,
    'FR-WIDTH_OF_30_PERCENT' => 31,
    'FR-WIDTH_OF_40_PERCENT' => 35,
    'FR-WIDTH_OF_50_PERCENT' => 41,
    'FR-WIDTH_OF_60_PERCENT' => 55,
    'FR-WIDTH_OF_70_PERCENT' => 65,
    'FR-WIDTH_OF_80_PERCENT' => 91,
    'FR-WIDTH_OF_90_PERCENT' => 119,
    'FR-WIDTH_OF_99_PERCENT' => 0,
);
is_deeply({$command->output_result->get_metrics}, {%expected_metrics}, 'Parsed metrics as expected');

$config_override->restore;

done_testing;
