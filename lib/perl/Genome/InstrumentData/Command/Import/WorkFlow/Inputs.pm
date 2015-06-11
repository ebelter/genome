package Genome::InstrumentData::Command::Import::WorkFlow::Inputs;

use strict;
use warnings;

use Params::Validate ':types';

use base 'Class::Accessor::Fast'; 
__PACKAGE__->mk_accessors(qw/
    analysis_project_id
    library_id
    instrument_data_properties
/);

use Genome;

sub new {
    my ($class, %params) = @_;

    my $self = bless(\%params, $class);
    $self->{instrument_data_properties} ||= {};

    for my $property_name (qw/ analysis_project_id library_id source_files /) {
        my $value = $self->{$property_name};
        die "ERROR: No $property_name given to work flow inputs!" if not $value;
        my $method = $property_name;
        next unless $method =~ s/_id$//;
        die "ERROR: No $property_name found for id: $value" if not $self->$method;
    }

    if ( not $self->instrument_data_properties->{original_data_path} ) {
        $self->instrument_data_properties->{original_data_path} = join(',', $self->source_files->paths);
    }

    return $self;
}

sub analysis_project {
    return Genome::Config::AnalysisProject->get($_[0]->analysis_project_id);
}

sub library {
    return Genome::Library->get($_[0]->library_id);
}

sub add_process {
    my ($self, $process) = Params::Validate::validate_pos(@_, {type => OBJECT}, {type => OBJECT});
    return $self->{instrument_data_properties}->{process_id} = $process->id;
}

sub process {
    return if not $_[0]->{instrument_data_properties}->{process_id};
    return Genome::InstrumentData::Command::Import::Process->get($_[0]->{instrument_data_properties}->{process_id});
}

sub source_files {
    return Genome::InstrumentData::Command::Import::WorkFlow::SourceFiles->create(paths => $_[0]->{source_files}) 
}

sub format {
    return $_[0]->source_files->format;
}

sub instrument_data_for_original_data_path {
    my $self = shift;
    my @odp_attrs = Genome::InstrumentDataAttribute->get(
        attribute_label => 'original_data_path',
        attribute_value => $self->source_files->original_data_path,
    );
    return if not @odp_attrs;
    return map { $_->instrument_data } @odp_attrs;
}

sub as_hashref {
    my $self = shift;
    return {
        analysis_project => $self->analysis_project,
        downsample_ratio => $self->instrument_data_properties->{downsample_ratio},
        instrument_data_properties => $self->instrument_data_properties,
        library => $self->library,
        library_name => $self->library->name,
        sample_name => $self->library->sample_name,
        source_paths => $self->{source_files},
    };
}

1;

