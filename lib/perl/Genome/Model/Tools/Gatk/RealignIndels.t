#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above 'Genome';

use Test::More;

if (Genome::Config->arch_os ne 'x86_64') {
    plan skip_all => 'requires 64-bit machine';
}
else {
    plan tests => 9;
}

use_ok('Genome::Model::Tools::Gatk::RealignIndels');

# Inputs
my $test_data_dir = $ENV{GENOME_TEST_INPUTS} . '/Genome-Model-Tools-Gatk-RealignIndels';
my $tumor_bam = "$test_data_dir/tumor.bam";
my $normal_bam = "$test_data_dir/normal.bam";
my $reference_fasta = "/gscmnt/ams1102/info/model_data/2869585698/build106942997/all_sequences.fa";
my $small_indel_list = "$test_data_dir/small_indels.padded1bp.bed";

# Outputs
my $output_dir = File::Temp::tempdir('VarscanValidationXXXXX', CLEANUP => 1, TMPDIR => 1);
my $output_tumor = "$output_dir/tumor.bam";
my $output_normal = "$output_dir/normal.bam";

# Expected
my $expected_dir = "$test_data_dir/1";
my $expected_tumor = "$expected_dir/tumor.realigned.bam";
my $expected_normal = "$expected_dir/normal.realigned.bam";

my $gatk_tumor_cmd = Genome::Model::Tools::Gatk::RealignIndels->create(
        max_memory => "4",
        version => 2.4,
        target_intervals => $small_indel_list,
        output_realigned_bam => $output_tumor,
        input_bam => $tumor_bam,
        reference_fasta => $reference_fasta,
        target_intervals_are_sorted => 0,
);

isa_ok($gatk_tumor_cmd, 'Genome::Model::Tools::Gatk::RealignIndels', "Made the tumor command");
ok(!$gatk_tumor_cmd->execute, "Failed to execute the tumor command when target intervals are not sorted");
# Can't really diff bams effectively as far as I know, so for now just make sure they exist

$gatk_tumor_cmd = Genome::Model::Tools::Gatk::RealignIndels->create(
        max_memory => "4",
        version => 2.4,
        target_intervals => $small_indel_list,
        output_realigned_bam => $output_tumor,
        input_bam => $tumor_bam,
        reference_fasta => $reference_fasta,
        target_intervals_are_sorted => 1,
);

isa_ok($gatk_tumor_cmd, 'Genome::Model::Tools::Gatk::RealignIndels', "Made the tumor command");
ok($gatk_tumor_cmd->execute, "Executed the tumor command when target intervals are sorted");
ok(-s $output_tumor, "Realigned tumor bam exists");

my $gatk_normal_cmd = Genome::Model::Tools::Gatk::RealignIndels->create(
        max_memory => "4",
        version => 5777,
        target_intervals => $small_indel_list,
        output_realigned_bam => $output_normal,
        input_bam => $normal_bam,
        reference_fasta => $reference_fasta,
        target_intervals_are_sorted => 0,
    );

isa_ok($gatk_normal_cmd, 'Genome::Model::Tools::Gatk::RealignIndels', "Made the normal command");
ok($gatk_normal_cmd->execute, "Executed the normal command");
# Can't really diff bams effectively as far as I know, so for now just make sure they exist
ok(-s $output_normal, "Realigned normal bam exists");
