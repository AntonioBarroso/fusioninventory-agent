package FusionInventory::Agent::Task::Inventory::OS::Win32::Software;

use strict;
use warnings;

use Config;

use Win32::OLE('in');
use Win32::OLE::Variant;

use FusionInventory::Agent::Task::Inventory::OS::Win32;

use Win32::TieRegistry ( Delimiter=>"/", ArrayValues=>0 );

sub isInventoryEnabled {1}

sub hexToDec {
    my $val = shift;

    return unless $val;

    return $val unless $val =~ /^0x/; 

    my $tmp = $val;

    $tmp =~ s/^0x0*//i;
    return hex($tmp); 
}

sub dateFormat {
    my ($installDate) = @_; 

    return unless $installDate;

    if ($installDate =~ /^(\d{4})(\d{2})(\d{2})/) {
        return "$3/$2/$1";
    } else { 
        return;
    }
}

sub processSoftwares {
    my $params = shift;

    my $softwares = $params->{softwares};

    my $inventory = $params->{inventory};
    my $is64bit = $params->{is64bit};

    foreach my $guid ( keys %$softwares ) {
        my $data = $softwares->{$guid};
        next unless keys %$data;

# odd, found on Win2003
        next unless keys %$data > 2;


        my $name = encodeFromRegistry($data->{'/DisplayName'});
# Use the folder name if there is no DisplayName
        $name = encodeFromRegistry($_) unless $name;
        my $comments = encodeFromRegistry($data->{'/Comments'});
        my $version = encodeFromRegistry($data->{'/DisplayVersion'});
        my $publisher = encodeFromRegistry($data->{'/Publisher'});
        my $urlInfoAbout = encodeFromRegistry($data->{'/URLInfoAbout'});
        my $helpLink = encodeFromRegistry($data->{'/HelpLink'});
        my $uninstallString = encodeFromRegistry($data->{'/UninstallString'});
        my $noRemove;
        my $releaseType = encodeFromRegistry($data->{'/ReleaseType'});
        my $installDate = dateFormat($data->{'/InstallDate'});
        my $versionMinor = hexToDec($data->{'/VersionMinor'});
        my $versionMajor = hexToDec($data->{'/VersionMajor'});


        if ($data->{'/NoRemove'}) {
            $noRemove = ($data->{'/NoRemove'} =~ /1/)?1:0;
        }

        $inventory->addSoftware ({
                COMMENTS => $comments,
#            FILESIZE => $filesize,
#            FOLDER => $folder,
                FROM => "registry",
                HELPLINK => $helpLink,
                INSTALLDATE => $installDate,
                NAME => $name,
                NOREMOVE => $noRemove,
                RELEASETYPE => $releaseType,
                PUBLISHER => $publisher,
                UNINSTALL_STRING => $uninstallString,
                URL_INFO_ABOUT => $urlInfoAbout,
                VERSION => $version,
                VERSION_MINOR => $versionMinor,
                VERSION_MAJOR => $versionMajor,
                IS64BIT => $is64bit,
                GUID => $guid,
                });
    }
}

sub doInventory {
    my $params = shift;

    my $inventory = $params->{inventory};

    my $KEY_WOW64_64KEY = 0x100; 
    my $KEY_WOW64_32KEY = 0x200; 


    my $Config;

    if ($Config{use64bitint}) {
# I don't know why but on Vista 32bit, KEY_WOW64_64KEY is able to read 32bit
# entries. This is not the case on Win2003 and if I correctly understand
# MSDN, this sounds very odd

        my $machKey64bit= $Registry->Open( "LMachine", {Access=>Win32::TieRegistry::KEY_READ()|$KEY_WOW64_64KEY,Delimiter=>"/"} );

        my $softwares=
            $machKey64bit->{"SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall"};
        processSoftwares({ inventory => $inventory, softwares => $softwares, is64bit => 1});

        my $machKey32bit= $Registry->Open( "LMachine", {Access=>Win32::TieRegistry::KEY_READ()|$KEY_WOW64_32KEY,Delimiter=>"/"} );

        $softwares=
            $machKey32bit->{"SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall"};

        processSoftwares({ inventory => $inventory, softwares => $softwares, is64bit => 0});

    } else {
        my $machKey= $Registry->Open( "LMachine", {Access=>Win32::TieRegistry::KEY_READ(),Delimiter=>"/"} );

        my $softwares=
            $machKey->{"SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall"};

        processSoftwares({ inventory => $inventory, softwares => $softwares, is64bit => 0});

    }

# Copyright (c) 2009 Megagram
# Code from Win32::WindowsUpdate
#    my $updateSession = Win32::OLE->new("Microsoft.Update.Session") or die "WMI connection failed.\n";
#    my $updateSearcher = $updateSession->CreateUpdateSearcher() or die;
#    my $queryResult = $updateSearcher->Search("Isinstalled = 1");
#    
#    my $updates = $queryResult->Updates;
#    foreach my $update (in $updates) {
#        my $id = $update->Identity->UpdateID;
#        my $kb;
#        foreach (in $update->KBArticleIDs) {
#            $kb.="/" if $kb;
#            $kb.="KB".$_;
#        }
#        $inventory->addUpdate({
#
#                ID => $id, 
#                KB => $kb
#
#                });
#    }

}
1;
