package FusionInventory::Agent::Task::NetInventory::Manufacturer::Cisco;

use strict;
use warnings;

use FusionInventory::Agent::Task::NetInventory::Manufacturer;
use FusionInventory::Agent::Tools::Network;
use FusionInventory::Agent::SNMP qw(getLastElement getNextToLastElement);

sub setConnectedDevicesMacAddresses {
    my (%params) = @_;

    # use generic code, with vlan-specific results
    FusionInventory::Agent::Task::NetInventory::Manufacturer::setConnectedDevicesMacAddresses(
        ports   => $params{ports},
        walks   => $params{walks},
        results => $params{results}->{VLAN}->{$params{vlan_id}}
    );
}

sub setTrunkPorts {
    my (%params) = @_;

    my $results = $params{results};
    my $ports   = $params{ports};

    while (my ($oid, $trunk) = each %{$results->{vlanTrunkPortDynamicStatus}}) {
        $ports->{getLastElement($oid)}->{TRUNK} = $trunk ? 1 : 0;
    }
}

sub setConnectedDevices {
    my (%params) = @_;

    my $results  = $params{results};
    my $ports    = $params{ports};
    my $walks    = $params{walks};

    return unless ref $results->{cdpCacheAddress} eq 'HASH';

    while (my ($oid, $ip_hex) = each %{$results->{cdpCacheAddress}}) {
        my $ip = hex2canonical($ip_hex);
        next if $ip eq '0.0.0.0';

        my $port_number =
            getNextToLastElement($oid) . "." . getLastElement($oid, -1);

	$ports->{getNextToLastElement($oid)}->{CONNECTIONS} = {
            CDP        => 1,
            CONNECTION => {
                IP      => $ip,
                IFDESCR => $results->{cdpCacheDevicePort}->{
                    $walks->{cdpCacheDevicePort}->{OID} . "." .$port_number
                },
                SYSDESCR => $results->{cdpCacheVersion}->{
                    $walks->{cdpCacheVersion}->{OID} . "." .$port_number
                },
                SYSNAME  => $results->{cdpCacheDeviceId}->{
                    $walks->{cdpCacheDeviceId}->{OID} . "." .$port_number
                },
                MODEL => $results->{cdpCachePlatform}->{
                    $walks->{cdpCachePlatform}->{OID} . "." .$port_number
                }
            }
        };
    }
}

1;
__END__

=head1 NAME

FusionInventory::Agent::Task::NetInventory::Manufacturer::Cisco - Cisco-specific functions

=head1 DESCRIPTION

This is a class defining some functions specific to Cisco hardware.

=head1 FUNCTIONS

=head2 setConnectedDevicesMacAddresses(%params)

Set mac addresses of connected devices.

=over

=item results raw values collected through SNMP

=item ports device ports list

=item walks model walk branch

=item vlan_id VLAN identifier

=back

=head2 setTrunkPorts(%params)

Set trunk bit on relevant ports.

=over

=item results raw values collected through SNMP

=item ports device ports list

=back

=head2 setConnectedDevices(%params)

Set connected devices, through CDP or LLDP.

=over

=item results raw values collected through SNMP

=item ports device ports list

=item walks model walk branch

=back
