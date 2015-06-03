package Genome::InstrumentData::Command::Import::Launch;

use strict;
use warnings;

use Genome;

use Genome::InstrumentData::Command::Import::CsvParser;
use Genome::InstrumentData::Command::Import::WorkFlow::Inputs;
use Genome::InstrumentData::Command::Import::WorkFlow::SourceFiles;
require List::Util;

class Genome::InstrumentData::Command::Import::Launch {
    is => 'Command::V2',
    doc => 'Manage importing sequence files into GMS',
    has => {
        analysis_project => {
            is => 'Genome::Config::AnalysisProject',
            doc => 'Analysis project to assign to the created instrument data.',
        },
        file => {
            is => 'Text',
            doc => 'The metadata file containing sequence file, library names and other infomation to be associated with instruemtn daa.',
        },
        job_group_name => {
            is => 'Text',
            doc => 'The job group name. Used to throttle imports to prvent too many running at a time.',
        },
    },
    has_optional => {
        mem => {
            is => 'Number',
            default_value => 8000,
            doc => 'Amount of memory in megabytes to request for each import.',
        },
    },
    has_optional_transient => {
        _imports => { is => 'Array', },
        gtmp => { is => 'Number', },
        process => { is => 'Genome::InstrumentData::Command::Import::Process', },
    },
};

sub help_brief {
    return 'batch import sequence files into GMS'
}

sub help_detail {
    my $help = <<HELP;
Given a metadata file, launch an import process that will import the sequence files in GMS. The launching of the jobs is handled a genome 'process'.

Listing status of a process:

\$ genome process view \$PROCESS_ID

Listing created instrument data:

\$ genome instrument-data list imported process_id=\$PROCESS_ID

About the Metadata File

HELP
    $help .= Genome::InstrumentData::Command::Import::CsvParser->csv_help;
    return $help;
}

sub execute {
    my $self = shift;

    $self->_check_for_running_processes;
    $self->_load_file;
    $self->_launch_process;

    return 1
}

sub _check_for_running_processes {
    my $self = shift;

    my $md5 = Genome::Sys->md5sum($self->file);
    die $self->error_message('Failed to get md5 for import file! %s', $self->file) if not $md5;

    my @active_processes = Genome::InstrumentData::Command::Import::Process->get(
        import_md5 => $md5,
        status => [qw/ New Scheduled Running /],
    );

    return 1 if not @active_processes;

    $self->debug_message("Found '%s' process (%s) for metadata file: %s", $active_processes[0]->status, $active_processes[0]->id, $self->file);
    die $self->error_message('Cannot start another import process until the previous one has completed!');
}

sub _load_file {
    my $self = shift;

    my $parser = Genome::InstrumentData::Command::Import::CsvParser->create(file => $self->file);
    my (%seen, @imports, @kb_required);
    while ( my $import = $parser->next ) {
        my $library_name = $import->{library}->{name};
        my $source_files = delete $import->{instdata}->{source_files};
        my $string = join(' ', $library_name, $source_files, map { $import->{instdata}->{$_} } keys %{$import->{instdata}});
        my $id = substr(Genome::Sys->md5sum_data($string), 0, 6);
        if ( $seen{$id} ) {
            die $self->error_message("Duplicate source file/library combination! $string");
        }
        $seen{$id}++;

        my @libraries = Genome::Library->get(name => $library_name);
        die $self->error_message('No library for name: %s', $library_name) if not @libraries;
        die $self->error_message('Multiple libraries for library name: %s', $library_name) if @libraries > 1;

        my $import = Genome::InstrumentData::Command::Import::WorkFlow::Inputs->new(
            analysis_project_id => $self->analysis_project->id,
            library_id => $libraries[0]->id,
            instrument_data_properties => $import->{instdata},
            source_files => [ split(',', $source_files) ], # FIXME move to csv parser
        );
        push @imports, $import;

        my $kb_required = $import->source_files->kilobytes_required_for_processing;
        $kb_required = 1048576 if $kb_required < 1048576; # 1 Gb 
        push @kb_required, $kb_required;
    }

    $self->_imports(\@imports);
    my $max_kb_required = List::Util::max(@kb_required);
    $self->gtmp( $max_kb_required / ( 1024 * 1024 ) );

    return 1;
}

sub _launch_process {
    my $self = shift;

    my $dag = Genome::WorkflowBuilder::DAG->create(name => 'Import Instrument Data for '.$self->file);
    my $gtmp = $self->gtmp;
    my $mem = $self->mem;
    my $lsf_resource = sprintf(
        "-g %s -M %s -R 'select [mem>%s & gtmp>%s] rsuage[mem=%s,gtmp=%s]", 
        $self->job_group_name, ($mem * 1024), $mem, $gtmp, $mem, $gtmp,
    );
    my $import_op = Genome::WorkflowBuilder::Command->create(
        name => 'InstData Import : Run WF',
        command => 'Genome::InstrumentData::Command::Import::WorkFlow::Run',
        lsf_resource => $lsf_resource,
    );
    $dag->connect_input(
        input_property => 'work_flow_inputs',
        destination => $import_op,
        destination_property => 'work_flow_inputs',
    );
    $dag->add_operation($import_op);
    $dag->parallel_by('work_flow_inputs');

    my $add_process_op = Genome::WorkflowBuilder::Command->create(
        name => 'InstData Import : Add Process',
        command => 'Genome::InstrumentData::Command::Import::WorkFlow::AddProcessToInstrumentData',
    );
    $dag->connect_input(
        input_property => 'process',
        destination => $add_process_op,
        destination_property => 'process',
    );
    $dag->create_link(
        source => $import_op,
        source_property => 'instrument_data',
        destination => $add_process_op,
        destination_property => 'instrument_data',
    );
    $dag->connect_output(
        output_property => 'instrument_data',
        source => $add_process_op,
        source_property => 'instrument_data',
    );
    $dag->add_operation($add_process_op);

    my $p = Genome::InstrumentData::Command::Import::Process->create(import_file => $self->file);
    $p->run(
        workflow_xml => $dag->get_xml,
        workflow_inputs => { 
            process => $p,
            work_flow_inputs => $self->_imports,
        },
    );
    $self->process($p);

    $self->debug_message('Started imports with process id: %s. View status with:', $p->id);
    $self->debug_message('genome instrument-data import status %s', $p->id);

    return 1;
}

1;

