#!/bin/bash
#
# IP Geolocation provided by either:
#
# DB-IP https://db-ip.com
#
# or 
#
# MaxMind https://www.maxmind.com

source /etc/geoip_key.conf 2>/dev/null 

function createPLdbip {
read -r -d '' VAR <<'EOF'
#!/usr/bin/perl
use NetAddr::IP;

unless(-s "$ARGV[0]"){
    print STDERR "Specify Country DB to use on the command line.\n";
    exit 1;
}

# Prime country data with additional continent codes
# http://download.geonames.org/export/dump/readme.txt
my $countryinfo;

# Read the countryinfo file
open my $fh_in, "<", "$ARGV[0]" or die "Can't open $ARGV[0]: $!\n";
foreach my $line (<$fh_in>){
    chomp $line;
    next if ($line =~ /^#/);
    my @fields = (split "\t", $line);
    my $code = $fields[0];
    my $name = $fields[4];
    $countryinfo->{$code}->{'name'} = $name;
}
close $fh_in;

foreach my $line (<STDIN>){
    next unless ($line =~ /^\d/);
    chomp $line;
    $counter++;
    my @fields = (split ",", $line);
    my $start_ip = $fields[0];
    my $end_ip = $fields[1];
    my $country_code = $fields[2];
    my $ip = NetAddr::IP->new($start_ip);
    my $ipend = NetAddr::IP->new($end_ip);
    my $start_int = $ip->bigint();
    my $end_int = $ipend->bigint();

    if($country_code eq "ZZ") {$country_code="US"; }

    $name = $countryinfo->{$country_code}->{'name'};

    print "\"$start_ip\",\"$end_ip\",\"$start_int\",\"$end_int\",\"$country_code\",\"$name\"\n"
}

EOF
echo "$VAR" > /usr/share/geoip/20_convert_dbip
chmod a+x /usr/share/geoip/20_convert_dbip
}

function createPL {
read -r -d '' VAR <<'EOF'
#!/usr/bin/perl -w
use strict;
use diagnostics;
use NetAddr::IP;
use Getopt::Long;

my $quiet = 0;
GetOptions(
    'quiet' => \$quiet,
    ) or die("bad args");

unless(-s "$ARGV[0]"){
	print STDERR "Specify Country DB to use on the command line.\n";
	exit 1;
}

# Prime country data with additional continent codes
# http://download.geonames.org/export/dump/readme.txt
my $countryinfo;
$countryinfo->{'6255146'}->{'code'} = 'AF';
$countryinfo->{'6255146'}->{'name'} = 'Africa';
$countryinfo->{'6255147'}->{'code'} = 'AS';
$countryinfo->{'6255147'}->{'name'} = 'Asia';
$countryinfo->{'6255148'}->{'code'} = 'EU';
$countryinfo->{'6255148'}->{'name'} = 'Europe';
$countryinfo->{'6255149'}->{'code'} = 'NA';
$countryinfo->{'6255149'}->{'name'} = 'North America';
$countryinfo->{'6255150'}->{'code'} = 'SA';
$countryinfo->{'6255150'}->{'name'} = 'South America';
$countryinfo->{'6255151'}->{'code'} = 'OC';
$countryinfo->{'6255151'}->{'name'} = 'Oceania';
$countryinfo->{'6255152'}->{'code'} = 'AN';
$countryinfo->{'6255152'}->{'name'} = 'Antarctica';

# Read the countryinfo file
open my $fh_in, "<", "$ARGV[0]" or die "Can't open $ARGV[0]: $!\n";
foreach my $line (<$fh_in>){
	chomp $line;
	next if ($line =~ /^#/);
	my @fields = (split "\t", $line);
	my $code = $fields[0];
	my $name = $fields[4];
	my $id   = $fields[16];
	$countryinfo->{$id}->{'code'} = $code;
	$countryinfo->{$id}->{'name'} = $name;
}
close $fh_in;

# Convert actual GeoLite2 data from STDIN
my $counter;
foreach my $line (<STDIN>){
	next unless ($line =~ /^\d/);
	chomp $line;
	$counter++;
	my @fields = (split ",", $line);
	my $network = $fields[0];
	my $geoname_id = $fields[1];
	my $registered_country_geoname_id = $fields[2];
	my $represented_country_geoname_id = $fields[3];
	my $is_anonymous_proxy = $fields[4];
	my $is_satellite_provider = $fields[5];
	my $ip = NetAddr::IP->new($network);
    my $addr = $ip->addr();
	#my $start_ip = $ip->canon();
    my $start_ip = _canon($addr);
	my $end_ip = $ip->broadcast();
	my $start_int = $ip->bigint();
	my $end_int = $end_ip->bigint();
	my $code;
	my $name;
	if ($is_anonymous_proxy){
		$code = "A1";
		$name = "Anonymous Proxy";
	}elsif ($is_satellite_provider){
		$code = "A2";
		$name = "Satellite Provider";
	}elsif($countryinfo->{$represented_country_geoname_id}){
		$code = $countryinfo->{$represented_country_geoname_id}->{'code'};
		$name = $countryinfo->{$represented_country_geoname_id}->{'name'};
	}elsif($countryinfo->{$registered_country_geoname_id}){
		$code = $countryinfo->{$registered_country_geoname_id}->{'code'};
		$name = $countryinfo->{$registered_country_geoname_id}->{'name'};
	}elsif($countryinfo->{$geoname_id}){
		$code = $countryinfo->{$geoname_id}->{'code'};
		$name = $countryinfo->{$geoname_id}->{'name'};
	}else{
		print STDERR "Unknown Geoname ID, panicking. This is a bug.\n";
		print STDERR "ID: $geoname_id\n";
		print STDERR "ID Registered: $registered_country_geoname_id\n";
		print STDERR "ID Represented $represented_country_geoname_id\n";
		exit 1;
	}

	# Legacy GeoIP listing format:
	# "1.0.0.0","1.0.0.255","16777216","16777471","AU","Australia"
	printf "\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"\n", 
		$start_ip, _canon($end_ip), $start_int, $end_int, $code, $name;
	if (!$quiet && $counter % 10000 == 0) {
		print STDERR "$counter\n";
	}
}

sub _canon {
    my $network = shift;
    my @partes = split(/\//,$network);
    my @octetos = split(/[:\.]/,$partes[0]);

    if($network =~ m/:/)  {
        # ipv6
        return lc(_compV6($partes[0]));
    } else {
        # ipv4
        return $octetos[0].".".$octetos[1].".".$octetos[2].".".$octetos[3];
    }
}

sub _compV6 ($) {
    my $ip = shift;
    return $ip unless my @candidates = $ip =~ /((?:^|:)0(?::0)+(?::|$))/g;
    my $longest = (sort { length($b) <=> length($a) } @candidates)[0];
    $ip =~ s/$longest/::/;
    return $ip;
}

EOF
echo "$VAR" > /usr/share/geoip/20_convert_geolite2
chmod a+x /usr/share/geoip/20_convert_geolite2
}

function fromGeolite2 {

    echo "Starting..." >/var/log/geoip_update.log

    cd /usr/share/geoip

    if [ "$LICENSE_KEY" = ""  ]; then

        echo "No MaxMind key setup, using DB-IP" >>/var/log/geoip_update.log

        # Download db-ip database
        timestamp=$(date "+%Y-%m")
        wget -q "https://download.db-ip.com/free/dbip-country-lite-$timestamp.csv.gz" -O- | \
                gzip -cd >dbip-country-lite.csv

        if [ "$?" -eq "1" ]; then
            MSG='GeoIP problem. Unable to download DB-IP database.'
            echo "$MSG" >>/var/log/geoip_update.log
            RES=$(sqlite3 /var/www/db/acl.db "select count(*) from acl_notification where content='$MSG'")
            if [ "$RES" -eq "0" ]; then
               issabel-notification --level='error' --message="$MSG"
            fi
            echo $MSG
            exit 1
        fi

        COUNTRYURL='http://download.geonames.org/export/dump/countryInfo.txt'
        if ! curl -s $COUNTRYURL > /tmp/CountryInfo.txt
        then
            MSG='GeoIP problem. Could not download country Info'
            echo "$MSG" >>/var/log/geoip_update.log
            RES=$(sqlite3 /var/www/db/acl.db "select count(*) from acl_notification where content='$MSG'")
            if [ "$RES" -eq "0" ]; then
               issabel-notification --level='error' --message="$MSG"
            fi
            echo $MSG
            exit 1
        fi

        awk 'f{print} /^::/{print;f=1}' dbip-country-lite.csv >dbip-country-lite-ipv6.csv
        awk 'BEGIN {f=1} f{print} /^::/{f=0}' dbip-country-lite.csv  | head -n -1 >dbip-country-lite-ipv4.csv

        filesize=$(stat -c%s dbip-country-lite.csv)
        if (( filesize > 1000  )); then
 
            cat dbip-country-lite-ipv4.csv | ./20_convert_dbip /tmp/CountryInfo.txt > /tmp/GeoIP-legacy-IPv4.csv
            cat dbip-country-lite-ipv6.csv | ./20_convert_dbip /tmp/CountryInfo.txt > /tmp/GeoIP-legacy-IPv6.csv
            cat /tmp/GeoIP-legacy-IPv{4,6}.csv >GeoIP-legacy.csv

            geoip-csv-to-dat /tmp/GeoIP-legacy-IPv4.csv >/tmp/GeoIP.dat
            geoip-csv-to-dat -6 /tmp/GeoIP-legacy-IPv6.csv >/tmp/GeoIPv6.dat

            filesize=$(stat -c%s /tmp/GeoIP.dat)
            if (( filesize > 1000  )); then
                echo "/tmp/GeoIP.dat size $filesize, copy to /usr/share/GeoIP" >>/var/log/geoip_update.log
                rm -rf /usr/share/GeoIP/GeoIP.dat
                cp -f /tmp/GeoIP.dat /usr/share/GeoIP
            fi

            filesize=$(stat -c%s /tmp/GeoIPv6.dat)
            if (( filesize > 1000  )); then
                echo "/tmp/GeoIPv6.dat size $filesize, copy to /usr/share/GeoIP" >>/var/log/geoip_update.log
                rm -rf /usr/share/GeoIP/GeoIPv6.dat
                cp -f /tmp/GeoIPv6.dat /usr/share/GeoIP
            fi

            ./20_build_xtables GeoIP-legacy.csv /tmp/CountryInfo.txt

        else
            MSG='GeoIP problem. DB-IP database corrupt.'
            echo "$MSG" >>/var/log/geoip_update.log
            RES=$(sqlite3 /var/www/db/acl.db "select count(*) from acl_notification where content='$MSG'")
            if [ "$RES" -eq "0" ]; then
               issabel-notification --level='error' --message="$MSG"
            fi
            echo $MSG
            exit 1
        fi



    else
        # Download MaxMind database

        echo "Using MaxMind" >/var/log/geoip_update.log

        TEMPZIP=$(mktemp)
        #LICENSE_KEY=
        GEOLITEURL="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country-CSV&license_key=$LICENSE_KEY&suffix=zip"
        if ! curl -s $GEOLITEURL > $TEMPZIP
        then
            MSG='GeoIP problem. Unable to download database.'
            echo "$MSG" >>/var/log/geoip_update.log
            RES=$(sqlite3 /var/www/db/acl.db "select count(*) from acl_notification where content='$MSG'")
            if [ "$RES" -eq "0" ]; then
               issabel-notification --level='error' --message="$MSG"
            fi
            echo $MSG
            exit 1
        fi

        file $TEMPZIP | grep ASCII >/dev/null
        if [ "$?" -eq "0" ]; then
            MSG='GeoIP problem. Invalid or empty MaxMind License.'
            echo "$MSG" >>/var/log/geoip_update.log
            RES=$(sqlite3 /var/www/db/acl.db "select count(*) from acl_notification where content='$MSG'")
            if [ "$RES" -eq "0" ]; then
               issabel-notification --level='error' --message="$MSG"
            fi
            echo $MSG
            exit 1
        fi

        if ! unzip -d /tmp -o -j $TEMPZIP '*/GeoLite2-Country-Blocks*'
        then
            MSG='GeoIP problem. Could not unzip database'
            echo "$MSG" >>/var/log/geoip_update.log
            RES=$(sqlite3 /var/www/db/acl.db "select count(*) from acl_notification where content='$MSG'")
            if [ "$RES" -eq "0" ]; then
               issabel-notification --level='error' --message="$MSG"
            fi
            echo $MSG
            exit 1
        fi
        rm $TEMPZIP

        COUNTRYURL='http://download.geonames.org/export/dump/countryInfo.txt'
        if ! curl -s $COUNTRYURL > /tmp/CountryInfo.txt
        then
            MSG='GeoIP problem. Could not download country Info'
            echo "$MSG" >>/var/log/geoip_update.log
            RES=$(sqlite3 /var/www/db/acl.db "select count(*) from acl_notification where content='$MSG'")
            if [ "$RES" -eq "0" ]; then
               issabel-notification --level='error' --message="$MSG"
            fi
            echo $MSG
            exit 1
        fi

        cat /tmp/GeoLite2-Country-Blocks-IPv4.csv | ./20_convert_geolite2 /tmp/CountryInfo.txt > /tmp/GeoIP-legacy-IPv4.csv
        cat /tmp/GeoLite2-Country-Blocks-IPv6.csv | ./20_convert_geolite2 /tmp/CountryInfo.txt > /tmp/GeoIP-legacy-IPv6.csv
        cat /tmp/GeoIP-legacy-IPv{4,6}.csv >GeoIP-legacy.csv

        geoip-csv-to-dat /tmp/GeoIP-legacy-IPv4.csv >/tmp/GeoIP.dat
        geoip-csv-to-dat -6 /tmp/GeoIP-legacy-IPv6.csv >/tmp/GeoIPv6.dat

        filesize=$(stat -c%s /tmp/GeoIP.dat)
        if (( filesize > 1000  )); then
            echo "/tmp/GeoIP.dat size $filesize, copy to /usr/share/GeoIP" >>/var/log/geoip_update.log
            rm -rf /usr/share/GeoIP/GeoIP.dat
            cp -f /tmp/GeoIP.dat /usr/share/GeoIP
        fi

        filesize=$(stat -c%s /tmp/GeoIPv6.dat)
        if (( filesize > 1000  )); then
            echo "/tmp/GeoIPv6.dat size $filesize, copy to /usr/share/GeoIP" >>/var/log/geoip_update.log
            rm -rf /usr/share/GeoIP/GeoIPv6.dat
            cp -f /tmp/GeoIPv6.dat /usr/share/GeoIP
        fi

        ./20_build_xtables GeoIP-legacy.csv /tmp/CountryInfo.txt


    fi


}

cd /usr/share/geoip
mkdir -p /usr/share/xt_geoip

if [ ! -f /usr/share/geoip/20_convert_geolite2 ]
then
    createPL
fi

if [ ! -f /usr/share/geoip/20_convert_dbip ]
then
    createPLdbip
fi
fromGeolite2

alias cp=cp
cp -rf {BE,LE} /usr/share/xt_geoip
find BE -type f -exec cp {} /usr/share/xt_geoip \;
alias cp='cp -i'
