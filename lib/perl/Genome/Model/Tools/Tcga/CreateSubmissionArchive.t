#!/gsc/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Genome::Utility::Test qw(compare_ok);
use Genome::Test::Factory::Model::ReferenceAlignment;
use Genome::Test::Factory::Model::SomaticVariation;
use Genome::Test::Factory::Build;

my $class = "Genome::Model::Tools::Tcga::CreateSubmissionArchive";
use_ok($class);

my $base_dir = Genome::Utility::Test->data_dir_ok($class, "v2");


my $test_somatic_build = Genome::Test::Factory::Model::SomaticVariation->setup_somatic_variation_build();
$test_somatic_build->normal_build->subject->common_name("normal");
$test_somatic_build->normal_build->subject->extraction_label("TCGA-1");
$test_somatic_build->normal_build->subject->source->upn("TCGA-UPN-A");
$test_somatic_build->normal_build->model->target_region_set_name("11111001 capture chip set");
$test_somatic_build->normal_build->data_directory($base_dir."/refalign_dir");

$test_somatic_build->tumor_build->subject->common_name("tumor");
$test_somatic_build->tumor_build->subject->extraction_label("TCGA-2");
$test_somatic_build->tumor_build->model->target_region_set_name("SeqCap EZ Human Exome v2.0");
$test_somatic_build->tumor_build->data_directory($base_dir."/refalign_dir2");

$test_somatic_build->data_directory("$base_dir/somvar_dir");

my $cghub_ids = Genome::Sys->create_temp_file_path;
`echo "CGHub_ID\tTCGA_Name\tBAM_path\ncghub1\tTCGA-1\t/dev/null\ncghub2\tTCGA-2\t/dev/null" > $cghub_ids`;

my $archive_output_dir = Genome::Sys->create_temp_directory;
my $cmd = Genome::Model::Tools::Tcga::CreateSubmissionArchive->create(
    models => [$test_somatic_build->model],
    output_dir => $archive_output_dir,
    archive_name => "test_archive",
    archive_version => "1.0.0",
    cghub_id_file => $cghub_ids,
    create_archive => 1,
);
ok($cmd, "Command created");
ok($cmd->execute, "Command executed");
for my $outfile (qw(test_archive.Level_2.1.0.0/genome.wustl.edu.TCGA-UPN-A.snv.1.vcf test_archive.Level_2.1.0.0/genome.wustl.edu.TCGA-UPN-A.indel.1.vcf test_archive.Level_2.1.0.0/MANIFEST.txt test_archive.mage-tab.1.0.0/test_archive.1.0.0.idf.txt test_archive.mage-tab.1.0.0/test_archive.1.0.0.sdrf.txt)) {
    compare_ok("$archive_output_dir/$outfile", "$base_dir/archive_test/$outfile", replace => [['PP_ID' => $test_somatic_build->normal_build->processing_profile->id]], name => "file $outfile diffed correctly");
}

ok(-s "$archive_output_dir/test_archive.Level_2.1.0.0.tar.gz", "vcf archive was created");
ok(-s "$archive_output_dir/test_archive.Level_2.1.0.0.tar.gz.md5", "vcf archive was md5ed");
ok(-s "$archive_output_dir/test_archive.mage-tab.1.0.0.tar.gz", "magetab archive was created");
ok(-s "$archive_output_dir/test_archive.mage-tab.1.0.0.tar.gz.md5", "magetab archive was md5ed");
ok(-s "$archive_output_dir/test_archive.mage-tab.1.0.0/MANIFEST.txt", "magetab manifest was created");

done_testing;
