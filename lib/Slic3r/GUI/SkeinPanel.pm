package Slic3r::GUI::SkeinPanel;
use strict;
use warnings;
use utf8;

use File::Basename qw(basename dirname);
use Wx qw(:sizer :progressdialog wxOK wxICON_INFORMATION wxICON_WARNING wxICON_ERROR wxICON_QUESTION
    wxOK wxCANCEL wxID_OK wxFD_OPEN wxFD_SAVE wxDEFAULT wxNORMAL);
use Wx::Event qw(EVT_BUTTON);
use base 'Wx::Panel';

my $last_skein_dir;
my $last_config_dir;
our $last_config;

sub new {
    my $class = shift;
    my ($parent) = @_;
    my $self = $class->SUPER::new($parent, -1);
    
    my %panels = (
        printer => {
            title => 'Printer',
            options => [qw(nozzle_diameter print_center z_offset gcode_flavor use_relative_e_distances)],
        },
        filament => {
            title => 'Filament',
            options => [qw(filament_diameter extrusion_multiplier temperature first_layer_temperature)],
        },
        print_speed => {
            title => 'Print speed',
            options => [qw(perimeter_speed small_perimeter_speed infill_speed solid_infill_speed bridge_speed)],
        },
        speed => {
            title => 'Other speed settings',
            options => [qw(travel_speed bottom_layer_speed_ratio)],
        },
        accuracy => {
            title => 'Accuracy',
            options => [qw(layer_height first_layer_height_ratio infill_every_layers)],
        },
        print => {
            title => 'Print settings',
            options => [qw(perimeters solid_layers fill_density fill_angle fill_pattern solid_fill_pattern support_material support_material_tool)],
        },
        retract => {
            title => 'Retraction',
            options => [qw(retract_length retract_lift retract_speed retract_restart_extra retract_before_travel)],
        },
        cooling => {
            title => 'Cooling',
            options => [qw(cooling min_fan_speed max_fan_speed bridge_fan_speed fan_below_layer_time slowdown_below_layer_time min_print_speed disable_fan_first_layers fan_always_on)],
            label_width => 300,
        },
        skirt => {
            title => 'Skirt',
            options => [qw(skirts skirt_distance skirt_height)],
        },
        transform => {
            title => 'Transform',
            options => [qw(scale rotate duplicate_x duplicate_y duplicate_distance)],
        },
        gcode => {
            title => 'Custom GCODE',
            options => [qw(start_gcode end_gcode gcode_comments post_process)],
        },
        extrusion => {
            title => 'Extrusion',
            options => [qw(extrusion_width_ratio bridge_flow_ratio)],
        },
        output => {
            title => 'Output',
            options => [qw(output_filename_format)],
        },
        notes => {
            title => 'Notes',
            options => [qw(notes)],
        },
    );
    $self->{panels} = \%panels;

    if (eval "use Growl::GNTP; 1") {
        # register growl notifications
        eval {
            $self->{growler} = Growl::GNTP->new(AppName => 'Slic3r'); #, AppIcon => "path/to/my/icon.gif");
            $self->{growler}->register([{Name => 'SKEIN_DONE', DisplayName => 'Slicing Done'}]);
        };
    }
    
    my $tabpanel = Wx::Notebook->new($self, -1, Wx::wxDefaultPosition, Wx::wxDefaultSize, &Wx::wxNB_TOP);
    my $make_tab = sub {
        my @cols = @_;
        
        my $tab = Wx::Panel->new($tabpanel, -1);
        my $sizer = Wx::BoxSizer->new(wxHORIZONTAL);
        foreach my $col (@cols) {
            my $vertical_sizer = Wx::BoxSizer->new(wxVERTICAL);
            for my $optgroup (@$col) {
                my $optpanel = Slic3r::GUI::OptionsGroup->new($tab, %{$panels{$optgroup}});
                $vertical_sizer->Add($optpanel, 0, wxEXPAND | wxALL, 10);
            }
            $sizer->Add($vertical_sizer);
        }
        
        $tab->SetSizer($sizer);
        return $tab;
    };
    
    my @tabs = (
        $make_tab->([qw(transform accuracy skirt)], [qw(print retract)]),
        $make_tab->([qw(cooling)]),
        $make_tab->([qw(printer filament)], [qw(print_speed speed)]),
        $make_tab->([qw(gcode)]),
        $make_tab->([qw(notes)], [qw(extrusion output)]),
    );
    
    $tabpanel->AddPage($tabs[0], "Print");
    $tabpanel->AddPage($tabs[1], "Cooling");
    $tabpanel->AddPage($tabs[2], "Printer and Filament");
    $tabpanel->AddPage($tabs[3], "GCODE");
    $tabpanel->AddPage($tabs[4], "Advanced");
        
    my $buttons_sizer;
    {
        $buttons_sizer = Wx::BoxSizer->new(wxHORIZONTAL);
        
        
        my $buttons_left_sizer = Wx::BoxSizer->new(wxHORIZONTAL);
        $buttons_left_sizer->SetMinSize(300, 0);
        
        my $save_button = Wx::Button->new($self, -1, "Save Config…");
        $buttons_left_sizer->Add($save_button, 0);
        EVT_BUTTON($self, $save_button, sub { $self->save_config });
        
        $buttons_left_sizer->Add((14, 0), 0);
        
        my $load_button = Wx::Button->new($self, -1, "Open Config…");
        $buttons_left_sizer->Add($load_button, 0);
        EVT_BUTTON($self, $load_button, sub { $self->load_config });
        
        $buttons_sizer->Add($buttons_left_sizer, 1);
        
        
        my $font = Wx::Font->new(10, wxDEFAULT, wxNORMAL, wxNORMAL);
        my $update_sizer = Wx::BoxSizer->new(wxVERTICAL);
        
        {
            my $text = Wx::StaticText->new($self, -1, "Version $Slic3r::VERSION");
            $text->SetFont($font);
            $update_sizer->Add($text, 0, wxALIGN_CENTER);
        
            #my $link = Wx::HyperlinkCtrl->new($self, -1, "Check for updates at slic3r.org", "http://slic3r.org/");
            my $link = Wx::StaticText->new($self, -1, "Check for updates at http://slic3r.org/");
            $link->SetFont($font);
            $update_sizer->Add($link, 0, wxALIGN_CENTER);
        }
        
        $buttons_sizer->Add($update_sizer, 0, wxEXPAND);
        
        
        my $buttons_right_sizer = Wx::BoxSizer->new(wxHORIZONTAL);
        $buttons_right_sizer->SetMinSize(300, 0);
        
        $buttons_right_sizer->AddStretchSpacer();
        
        my $slice_button = Wx::Button->new($self, -1, "Slice…");
        $slice_button->SetDefault();
        $buttons_right_sizer->Add($slice_button, 0, wxALIGN_RIGHT);
        EVT_BUTTON($self, $slice_button, sub { $self->do_slice });
        
        $buttons_sizer->Add($buttons_right_sizer, 1, wxALIGN_RIGHT);
    }
    
    my $sizer = Wx::BoxSizer->new(wxVERTICAL);
    $sizer->Add($buttons_sizer, 0, wxEXPAND | wxALL, (14));
    $sizer->Add($tabpanel);
    
    $sizer->SetSizeHints($self);
    $self->SetSizer($sizer);
    $self->Layout;
    
    return $self;
}

my $model_wildcard = "STL files (*.stl)|*.stl;*.STL|AMF files (*.amf)|*.amf;*.AMF;*.xml;*.XML";
my $ini_wildcard = "INI files *.ini|*.ini;*.INI";
my $gcode_wildcard = "GCODE files *.gcode|*.gcode;*.GCODE";

sub do_slice {
    my $self = shift;
    my %params = @_;
    
    my $process_dialog;
    eval {
        # validate configuration
        Slic3r::Config->validate;

        # confirm slicing of more than one copies
        my $copies = Slic3r::Config->get('duplicate_x') * Slic3r::Config->get('duplicate_y');
        if ($copies > 1) {
            my $confirmation = Wx::MessageDialog->new($self, "Are you sure you want to slice $copies copies?",
                                                      'Confirm', wxICON_QUESTION | wxOK | wxCANCEL);
            return unless $confirmation->ShowModal == wxID_OK;
        }
        
        # select input file
        my $dir = $last_skein_dir || $last_config_dir || "";
        my $dialog = Wx::FileDialog->new($self, 'Choose a STL or AMF file to slice:', $dir, "", $model_wildcard, wxFD_OPEN);
        return unless $dialog->ShowModal == wxID_OK;
        my ($input_file) = $dialog->GetPaths;
        my $input_file_basename = basename($input_file);
        $last_skein_dir = dirname($input_file);
        
        my $skein = Slic3r::Skein->new(
            input_file  => $input_file,
            output_file => $main::opt{output},
            status_cb   => sub {
                my ($percent, $message) = @_;
                if (&Wx::wxVERSION_STRING =~ / 2\.(8\.|9\.[2-9])/) {
                    $process_dialog->Update($percent, "$message...");
                }
            },
        );

        # select output file
        if ($params{save_as}) {
            my $output_file = $skein->expanded_output_filepath;
            my $dlg = Wx::FileDialog->new($self, 'Save gcode file as:', dirname($output_file),
                basename($output_file), $gcode_wildcard, wxFD_SAVE);
            return if $dlg->ShowModal != wxID_OK;
            $skein->output_file($dlg->GetPath);
        }
        
        # show processbar dialog
        $process_dialog = Wx::ProgressDialog->new('Slicing...', "Processing $input_file_basename...", 
            100, $self, 0);
        $process_dialog->Pulse;
        
        {
            my @warnings = ();
            local $SIG{__WARN__} = sub { push @warnings, $_[0] };
            $skein->go;
            $self->catch_warning->($_) for @warnings;
        }
        $process_dialog->Destroy;
        undef $process_dialog;
        
        my $message = sprintf "%s was successfully sliced in %d minutes and %.3f seconds.",
            $input_file_basename, int($skein->processing_time/60),
            $skein->processing_time - int($skein->processing_time/60)*60;
        eval {
            $self->{growler}->notify(Event => 'SKEIN_DONE', Title => 'Slicing Done!', Message => $message)
                if ($self->{growler});
        };
        Wx::MessageDialog->new($self, $message, 'Done!', 
            wxOK | wxICON_INFORMATION)->ShowModal;
    };
    $self->catch_error(sub { $process_dialog->Destroy if $process_dialog });
}

sub save_config {
    my $self = shift;
    
    my $process_dialog;
    eval {
        # validate configuration
        Slic3r::Config->validate;
    };
    $self->catch_error(sub { $process_dialog->Destroy if $process_dialog }) and return;
    
    my $dir = $last_config ? dirname($last_config) : $last_config_dir || $last_skein_dir || "";
    my $filename = $last_config ? basename($last_config) : "config.ini";
    my $dlg = Wx::FileDialog->new($self, 'Save configuration as:', $dir, $filename, 
        $ini_wildcard, wxFD_SAVE);
    if ($dlg->ShowModal == wxID_OK) {
        my $file = $dlg->GetPath;
        $last_config_dir = dirname($file);
        $last_config = $file;
        Slic3r::Config->save($file);
    }
}

sub load_config {
    my $self = shift;
    
    my $dir = $last_config ? dirname($last_config) : $last_config_dir || $last_skein_dir || "";
    my $dlg = Wx::FileDialog->new($self, 'Select configuration to load:', $dir, "config.ini", 
        $ini_wildcard, wxFD_OPEN);
    if ($dlg->ShowModal == wxID_OK) {
        my ($file) = $dlg->GetPaths;
        $last_config_dir = dirname($file);
        $last_config = $file;
        eval {
            local $SIG{__WARN__} = $self->catch_warning;
            Slic3r::Config->load($file);
        };
        $self->catch_error();
        $_->() for @Slic3r::GUI::OptionsGroup::reload_callbacks;
    }
}

sub catch_error {
    my ($self, $cb) = @_;
    if (my $err = $@) {
        $cb->() if $cb;
        Wx::MessageDialog->new($self, $err, 'Error', wxOK | wxICON_ERROR)->ShowModal;
        return 1;
    }
    return 0;
}

sub catch_warning {
    my ($self) = @_;
    return sub {
        my $message = shift;
        Wx::MessageDialog->new($self, $message, 'Warning', wxOK | wxICON_WARNING)->ShowModal;
    };
};

1;
