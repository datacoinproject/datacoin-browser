use strict;

use Google::ProtocolBuffers;
use MIME::Base64 qw( encode_base64 decode_base64 );
use IO::Compress::Bzip2 qw(bzip2 $Bzip2Error);
use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error);
use Crypt::OpenSSL::RSA;
use Datacoin::JSON::RPC::Client;
use File::HomeDir;
use Data::Dumper;

use Datacoin::Envelope;
use Datacoin::Utils;

# Parse daemon config
my %harg = parse_args(\@ARGV);
my $config_path = File::HomeDir->my_home . "/.datacoin/" unless length($harg{config_path}) > 0;
my %conf = init_config($config_path);

# Initialize JSONRPC
my $daemon = new Datacoin::JSON::RPC::Client;
$daemon->ua->credentials("localhost:$conf{rpcport}", 'jsonrpc', $conf{rpcuser} => $conf{rpcpassword});
$daemon->ua->timeout(60);
my $uri = "http://localhost:$conf{rpcport}/";

# Compile header.proto
Google::ProtocolBuffers->parsefile("envelope.proto");

# Enumerate blocks
my $height = 18000;
while (1) {
  my $res = json_call($daemon, $uri, "getblockhash", [$height], sub {print STDERR "error while doing \"getblockhash $height\"\n";});
  if (!$res->{is_success}) { print STDERR Dumper($res); last; }
  my $blkhash = $res->{content}->{result};
  #print "$height $blkhash\n";
  if (0 == $height % 1000) { print STDERR "Height == $height\n"; }
  
  $res = json_call($daemon, $uri, "getblock", [$blkhash]);

  my @txes = @{$res->{content}->{result}->{tx}};
  foreach my $txhash (@txes) {
    $res = json_call($daemon, $uri, "getdata", [$txhash], sub {print STDERR "error fetching data from $txhash\n";});
    my $base64_data = $res->content->{result};

    if (0 == length($base64_data)) { next; }
    print "$height $txhash " . length($base64_data);

    my $content = decode_base64($base64_data);
    my $renv;
    eval { $renv = Envelope->decode($content); };
    if (exists $renv->{Data}) {
      print " " . join(" ", ($renv->{FileName}, $renv->{ContentType}, $renv->{Compression}));
    }
    print "\n";
  }

  $height += 1;
}

exit;

### 

sub analyse_tx {
  #my () = @_;
}

###

sub parse_args {
  my ($ra) = @_;
  my %h;

  foreach my $a (@{$ra}) {
    if ($a =~ /^--([a-zA-Z_\-]+)=(.*)$/) {
      $h{$1} = $2;
    } elsif (! exists $h{file}) {
      $h{id} = $a;
    } else {
      die "Can't parse \"$a\"";
    }
  }

  return %h;
}
