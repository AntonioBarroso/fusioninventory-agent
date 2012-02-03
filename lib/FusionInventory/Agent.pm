package FusionInventory::Agent;

use strict;
use warnings;

use Cwd;
use English qw(-no_match_vars);
use UNIVERSAL::require;
use File::Glob;

use FusionInventory::Agent::Config;
use FusionInventory::Agent::HTTP::Client::Fusion;
use FusionInventory::Agent::Logger;
use FusionInventory::Agent::Scheduler;
use FusionInventory::Agent::Storage;
use FusionInventory::Agent::Task;
use FusionInventory::Agent::Target::Local;
use FusionInventory::Agent::Target::Server;
use FusionInventory::Agent::Target::Stdout;
use FusionInventory::Agent::Tools;
use FusionInventory::Agent::Tools::Hostname;
use FusionInventory::Agent::XML::Query::Prolog;

our $VERSION = '2.1.9904';
our $VERSION_STRING = 
    "FusionInventory unified agent for UNIX, Linux and MacOSX ($VERSION)";
our $AGENT_STRING =
    "FusionInventory-Agent_v$VERSION";

sub new {
    my ($class, %params) = @_;

    my $self = {
        status  => 'unknown',
        confdir => $params{confdir},
        datadir => $params{datadir},
        libdir  => $params{libdir},
        vardir  => $params{vardir},
    };
    bless $self, $class;

    return $self;
}

sub init {
    my ($self, %params) = @_;

    my $config = FusionInventory::Agent::Config->new(
        confdir => $self->{confdir},
        options => $params{options},
    );
    $self->{config} = $config;

    my $logger = FusionInventory::Agent::Logger->new(
        config   => $config,
        backends => $config->{logger},
        debug    => $config->{debug}
    );
    $self->{logger} = $logger;

    if ( $REAL_USER_ID != 0 ) {
        $logger->info("You should run this program as super-user.");
    }

    $logger->debug("Configuration directory: $self->{confdir}");
    $logger->debug("Data directory: $self->{datadir}");
    $logger->debug("Storage directory: $self->{vardir}");
    $logger->debug("Lib directory: $self->{libdir}");

    $self->{storage} = FusionInventory::Agent::Storage->new(
        logger    => $logger,
        directory => $self->{vardir}
    );

    # handle persistent state
    $self->_loadState();

    $self->{deviceid} = _computeDeviceId() if !$self->{deviceid};
    $self->{token}    = _computeToken()    if !$self->{token};

    $self->_saveState();

    my $client = FusionInventory::Agent::HTTP::Client::Fusion->new(
          logger       => $self->{logger},
          user         => $self->{config}->{user},
          password     => $self->{config}->{password},
          proxy        => $self->{config}->{proxy},
          ca_cert_file => $self->{config}->{'ca-cert-file'},
          ca_cert_dir  => $self->{config}->{'ca-cert-dir'},
          no_ssl_check => $self->{config}->{'no-ssl-check'},
    );
    $self->{client} = $client;

    $self->{scheduler} = FusionInventory::Agent::Scheduler->new(
        client     => $client,
        logger     => $logger,
        lazy       => $config->{lazy},
        wait       => $config->{wait},
        tasks      => \%available,
        background => $config->{daemon} || $config->{service}
    );
    my $scheduler = $self->{scheduler};

    # create target list
    if ($config->{stdout}) {
        $scheduler->addTarget(
            FusionInventory::Agent::Target::Stdout->new(
                logger     => $logger,
                deviceid   => $self->{deviceid},
                delaytime  => $config->{delaytime},
                basevardir => $self->{vardir},
            )
        );
    }

    if ($config->{local}) {
        $scheduler->addTarget(
            FusionInventory::Agent::Target::Local->new(
                logger     => $logger,
                deviceid   => $self->{deviceid},
                delaytime  => $config->{delaytime},
                basevardir => $self->{vardir},
                path       => $config->{local},
            )
        );
    }

    if ($config->{server}) {
        foreach my $url (@{$config->{server}}) {
            $scheduler->addTarget(
                FusionInventory::Agent::Target::Server->new(
                    logger     => $logger,
                    deviceid   => $self->{deviceid},
                    delaytime  => $config->{delaytime},
                    basevardir => $self->{vardir},
                    url        => $url,
                    tag        => $config->{tag},
                )
            );
        }
    }

    if (!$scheduler->getTargets()) {
        $logger->error("No target defined, aborting");
        exit 1;
    }

    if ($config->{daemon} && !$config->{'no-fork'}) {

        $logger->debug("Time to call Proc::Daemon");

        Proc::Daemon->require();
        if ($EVAL_ERROR) {
            $logger->error("Can't load Proc::Daemon. Is the module installed?");
            exit 1;
        }
        Proc::Daemon::Init();
        $logger->debug("Daemon started");
        if ($self->_isAlreadyRunning()) {
            $logger->debug("An agent is already runnnig, exiting...");
            exit 1;
        }
    }

    if (($config->{daemon} || $config->{service}) && !$config->{'no-httpd'}) {
        FusionInventory::Agent::HTTP::Server->require();
        if ($EVAL_ERROR) {
            $logger->debug("Failed to load HTTP server: $EVAL_ERROR");
        } else {
            # make sure relevant variables are shared between threads
            threads::shared->require();
            # calling share(\$self->{status}) directly breaks in testing
            # context, hence the need to use an intermediate variable
            my $status = \$self->{status};
            my $token = \$self->{token};
            threads::shared::share($status);
            threads::shared::share($token);

            $_->setShared() foreach $scheduler->getTargets();

            $self->{server} = FusionInventory::Agent::HTTP::Server->new(
                logger          => $logger,
                scheduler       => $scheduler,
                agent           => $self,
                htmldir         => $self->{datadir} . '/html',
                ip              => $config->{'httpd-ip'},
                port            => $config->{'httpd-port'},
                trust           => $config->{'httpd-trust'},
            );
        }
    }

    $logger->debug("FusionInventory Agent initialised");
}

sub run {
    my ($self) = @_;

    $self->{status} = 'waiting';

    # endless loop in server mode
    while (my ($target, $tasksExecPlan) = $self->{scheduler}->getNextTarget()) {
        last unless $tasksExecPlan;
        eval {
            $self->_runTarget($target, $tasksExecPlan);
        };
        $self->{logger}->fault($EVAL_ERROR) if $EVAL_ERROR;
        # $target->resetNextRunDate(); TODO
    }
}

sub _runTarget {
    my ($self, $target, $tasksExecPlan) = @_;

    eval {
       $self->_runTask($target, $tasksExecPlan);
    };
    $self->{logger}->error($EVAL_ERROR) if $EVAL_ERROR;
    $self->{status} = 'waiting';
}

sub _runTask {
    my ($self, $target, $tasksExecPlan) = @_;

    my $class = "FusionInventory::Agent::Task::".$tasksExecPlan->{task};
    my $task = $class->new(
        config       => $self->{config},
        confdir      => $self->{confdir},
        datadir      => $self->{datadir},
        logger       => $self->{logger},
        target       => $target,
        deviceid     => $self->{deviceid}
    );

    $self->{status} = "running task ".$tasksExecPlan->{task};

    if ($self->{config}->{daemon} || $self->{config}->{service}) {
        # daemon mode: run each task in a child process
        if (my $pid = fork()) {
            # parent
            waitpid($pid, 0);
        } else {
            # child
            die "fork failed: $ERRNO" unless defined $pid;

            $self->{logger}->debug("running task ".$tasksExecPlan->{task}." in process $PID");
            $task->run(
                user         => $self->{config}->{user},
                password     => $self->{config}->{password},
                proxy        => $self->{config}->{proxy},
                ca_cert_file => $self->{config}->{'ca-cert-file'},
                ca_cert_dir  => $self->{config}->{'ca-cert-dir'},
                no_ssl_check => $self->{config}->{'no-ssl-check'},
                remote       => $tasksExecPlan->{remote}
                );
            exit(0);
        }
    } else {
        # standalone mode: run each task directly
        $self->{logger}->debug("running task ".$tasksExecPlan->{task});
        $task->run(
            user         => $self->{config}->{user},
            password     => $self->{config}->{password},
            proxy        => $self->{config}->{proxy},
            ca_cert_file => $self->{config}->{'ca-cert-file'},
            ca_cert_dir  => $self->{config}->{'ca-cert-dir'},
            no_ssl_check => $self->{config}->{'no-ssl-check'},
            remote       => $tasksExecPlan->{remote}
        );
    }
}

sub getToken {
    my ($self) = @_;
    return $self->{token};
}

sub resetToken {
    my ($self) = @_;
    $self->{token} = _computeToken();
}

sub getStatus {
    my ($self) = @_;
    return $self->{status};
}

sub getAvailableTasks {
    my ($self, %params) = @_;

    my $logger = $self->{logger};
    my %tasks;
    my %disabled  = map { lc($_) => 1 } @{$params{disabledTasks}};

    # tasks may be located only in agent libdir
    my $directory = $self->{libdir};
    $directory =~ s,\\,/,g;
    my $subdirectory = "FusionInventory/Agent/Task";
    # look for all perl modules here
    foreach my $file (File::Glob::glob("$directory/$subdirectory/*.pm")) {
        next unless $file =~ m{($subdirectory/(\S+)\.pm)$};
        my $module = file2module($1);
        my $name = file2module($2);

        next if $disabled{lc($name)};

        # check module
        # todo: use a child process when running as a server to save memory
        if (!$module->require()) {
            $logger->debug2("module $module does not compile") if $logger;
            next;
        }
        if (!$module->isa('FusionInventory::Agent::Task')) {
            $logger->debug2("module $module is not a task") if $logger;
            next;
        }

        # retrieve version
        my $version;
        {
            no strict 'refs';  ## no critic
            $version = ${$module . '::VERSION'};
        }

        $tasks{$name} = $version;
    }

    return %tasks;
}

sub _isAlreadyRunning {
    my ($self) = @_;

    Proc::PID::File->require();
    if ($EVAL_ERROR) {
        $self->{logger}->debug(
            'Proc::PID::File unavailable, unable to check for running agent'
        );
        return 0;
    }

    return Proc::PID::File->running();
}

sub _loadState {
    my ($self) = @_;

    my $data = $self->{storage}->restore(name => 'FusionInventory-Agent');

    $self->{token}    = $data->{token}    if $data->{token};
    $self->{deviceid} = $data->{deviceid} if $data->{deviceid};
}

sub _saveState {
    my ($self) = @_;

    $self->{storage}->save(
        name => 'FusionInventory-Agent',
        data => {
            token    => $self->{token},
            deviceid => $self->{deviceid},
        }
    );
}

# compute a random token
sub _computeToken {
    my @chars = ('A'..'Z');
    return join('', map { $chars[rand @chars] } 1..8);
}

# compute an unique agent identifier, based on host name and current time
sub _computeDeviceId {
    my $hostname = FusionInventory::Agent::Tools::Hostname::getHostname();

    my ($year, $month , $day, $hour, $min, $sec) =
        (localtime (time))[5, 4, 3, 2, 1, 0];

    return sprintf "%s-%02d-%02d-%02d-%02d-%02d-%02d",
        $hostname, $year + 1900, $month + 1, $day, $hour, $min, $sec;
}

1;
__END__

=head1 NAME

FusionInventory::Agent - Fusion Inventory agent

=head1 DESCRIPTION

This is the agent object.

=head1 METHODS

=head2 new(%params)

The constructor. The following parameters are allowed, as keys of the %params
hash:

=over

=item I<confdir>

the configuration directory.

=item I<datadir>

the read-only data directory.

=item I<vardir>

the read-write data directory.

=item I<options>

the options to use.

=back

=head2 init()

Initialize the agent.

=head2 run()

Run the agent.

=head2 getToken()

Get the current authentication token.

=head2 resetToken()

Set the current authentication token to a random value.

=head2 getStatus()

Get the current agent status.

=head2 getAvailableTasks()

Get all available tasks found on the system, as a list of module / version
pairs:

%tasks = (
    'FusionInventory::Agent::Task::Foo' => x,
    'FusionInventory::Agent::Task::Bar' => y,
);
