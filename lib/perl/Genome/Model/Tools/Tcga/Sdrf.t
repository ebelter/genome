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
use Genome::Test::Factory::Model::SomaticVariation;

my $class = "Genome::Model::Tools::Tcga::Sdrf";
my $base_dir = Genome::Utility::Test->data_dir_ok($class, "v1");

subtest "create sdrf" => sub {
    my $sdrf = $class->create;
    ok($sdrf, "sdrf created");
};

subtest "headers" => sub {
    my $sdrf = $class->create;
    my @headers = $sdrf->get_sdrf_headers;
    my @expected_headers = get_expected_headers();
    is_deeply(\@headers, \@expected_headers, "Headers generated correctly");
};

subtest "fill in nulls" => sub {
    my %empty_row;
    my $sdrf = $class->create;
    my $null_row = $sdrf->fill_in_nulls(\%empty_row);
    my @empty_keys = sort keys %$null_row;
    my @expected_headers = get_expected_headers();
    my @sorted_headers = sort @expected_headers;
    is_deeply(\@empty_keys, \@sorted_headers, "Empty row got filled in");
};

subtest "print sdrf" => sub {
    my %empty_row;
    my $sdrf = $class->create;
    my $null_row = $sdrf->fill_in_nulls(\%empty_row);
    my $test_output = Genome::Sys->create_temp_file_path;
    ok($class->print_sdrf($test_output, $null_row), "print_sdrf ran ok with a row of nulls");
    compare_ok($test_output, $base_dir."/expected_null.sdrf", "null sdrf printed correctly");
};

subtest "testPrintSdrf" => sub {
    my $idf = Genome::Model::Tools::Tcga::Idf->create;
    my $sdrf = $class->create;

    my $test_somatic_build = setup_test_build();
    my $cghub_ids = setup_cghubids_file();

    my $sample_1 = {
        ID => {content => "TCGA_1"},
        SampleUUID => {content => "3958t6"},
        SampleTCGABarcode => {content => "TCGA_1"},
    };

    my $row1 = $sdrf->create_vcf_row($test_somatic_build->normal_build, "test_archive", $cghub_ids, "snvs.vcf", $sample_1, $idf);
    my $row2 = $sdrf->create_vcf_row($test_somatic_build->normal_build, "test_archive", $cghub_ids, "indels.vcf", $sample_1, $idf);
    my $row3 = $sdrf->create_maf_row($test_somatic_build->normal_build, "test_archive", "/test/maf/path", $cghub_ids, $sample_1, $idf);
    my $row4 = $sdrf->create_maf_row($test_somatic_build->tumor_build, "test_archive", "/test/maf/path", $cghub_ids, $sample_1, $idf);

    my $output_sdrf = Genome::Sys->create_temp_file_path;
    ok($sdrf->print_sdrf($output_sdrf, ($row1, $row2, $row3, $row4)), "sdrf printed");
};

subtest load_cghub_id => sub {
    my $cghub_ids = setup_cghubids_file();
    is_deeply($class->load_cghub_info($cghub_ids, "TCGA_Name"), {"TCGA-1" => "cghub1", "TCGA-2" => "cghub2"}, "CGHub info loaded correctly");
};

subtest "resolve cghub id" => sub {
    my $cghub_ids = setup_cghubids_file();
    my $test_somatic_build = setup_test_build();
    is($class->resolve_cghub_id($test_somatic_build->normal_build, $cghub_ids), "cghub1", "CGHub called correctly");
};

subtest "resolve capture reagent" => sub {
    my $test_somatic_build = setup_test_build();
    is_deeply([$class->resolve_capture_reagent($test_somatic_build->normal_build)], ["Nimblegen", "Nimblegen EZ Exome v3.0", "06465692001"], "Capture reagent resolved correctly");
};

sub setup_cghubids_file {
    my $cghub_ids = Genome::Sys->create_temp_file_path;
    `echo "CGHub_ID\tTCGA_Name\tBAM_path\ncghub1\tTCGA-1\t/dev/null\ncghub2\tTCGA-2\t/dev/null" > $cghub_ids`;
    return $cghub_ids;
}

sub setup_test_build {
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

    return $test_somatic_build;
}

sub get_expected_headers {
    return (
            'Material Extract Name',
            'Material Comment [TCGA Barcode]',
            'Material Comment [is tumor]',
            'Material Material Type',
            'Material Annotation REF',
            'Material Comment [TCGA Genome Reference]',
            'Library Protocol REF',
            'Library Parameter Value [Vendor]',
            'Library Parameter Value [Catalog Name]',
            'Library Parameter Value [Catalog Number]',
            'Library Parameter Value [Annotation URL]',
            'Library Parameter Value [Product URL]',
            'Library Parameter Value [Target File URL]',
            'Library Parameter Value [Target File Format]',
            'Library Parameter Value [Target File Format Version]',
            'Library Parameter Value [Probe File URL]',
            'Library Parameter Value [Probe File Format]',
            'Library Parameter Value [Probe File Format Version]',
            'Library Parameter Value [Target Reference Accession]',
            'Sequencing Protocol REF',
            'Mapping Protocol REF',
            'Mapping Comment [Derived Data File REF]',
            'Mapping Comment [TCGA CGHub ID]',
            'Mapping Comment [TCGA CGHub metadata URL]',
            'Mapping Comment [TCGA Include for Analysis]',
            'Mapping2 Derived Data File',
            'Mapping2 Comment [TCGA Include for Analysis]',
            'Mapping2 Comment [TCGA Data Type]',
            'Mapping2 Comment [TCGA Data Level]',
            'Mapping2 Comment [TCGA Archive Name]',
            'Mapping2 Parameter Value [Protocol Min Base Quality]',
            'Mapping2 Parameter Value [Protocol Min Map Quality]',
            'Mapping2 Parameter Value [Protocol Min Tumor Coverage]',
            'Mapping2 Parameter Value [Protocol Min Normal Coverage]',
            'Variants Protocol REF',
            'Variants Derived Data File',
            'Variants Comment [TCGA Spec Version]',
            'Variants Comment [TCGA Include for Analysis]',
            'Variants Comment [TCGA Data Type]',
            'Variants Comment [TCGA Data Level]',
            'Variants Comment [TCGA Archive Name]',
            'Maf Protocol REF',
            'Maf Derived Data File',
            'Maf Comment [TCGA Spec Version]',
            'Maf Comment [TCGA Include for Analysis]',
            'Maf Comment [TCGA Data Type]',
            'Maf Comment [TCGA Data Level]',
            'Maf Comment [TCGA Archive Name]',
            'Validation Protocol REF',
            'Validation Derived Data File',
            'Validation Comment [TCGA Spec Version]',
            'Validation Comment [TCGA Include for Analysis]',
            'Validation Comment [TCGA Data Type]',
            'Validation Comment [TCGA Data Level]',
            'Validation Comment [TCGA Archive Name]'
                );
}

done_testing;
