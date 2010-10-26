#!/usr/bin/perl -w
use strict;
use POSIX qw/strftime/;
use LWP::Simple;
use Fcntl ':flock';
use HTML::Entities;
use Time::Local;
use Cwd;

# get_show function authored by tvrage.com
# available at http://tvrage.com/info/quickinfo.html
use LWP::Simple;
sub get_show {
my ($show) = $_[0];
my ($exact ) = $_[1];
my ($episode) = $_[2];
my @ret = "";
if ( $show ne "" ){
	my $site = get "http://services.tvrage.com/tools/quickinfo.php?show=".$show."&ep=".$episode."&exact=".$exact;
	foreach my $line (split("\n",$site) ){
		my ($sec,$val) = split('\@',$line,2);
		if ($sec eq "Show Name" ){$ret[0] = $val;}
		elsif ( $sec eq "Show URL" ){$ret[1] = $val;}
		elsif ( $sec eq "Premiered" ){$ret[2] = $val;}
		elsif ($sec eq "Country" ){$ret[7] = $val;}
		elsif ( $sec eq "Status" ){$ret[8] = $val;}
		elsif ( $sec eq "Classification" ){$ret[9] = $val;}
		elsif ( $sec eq "Genres" ){$ret[10] = $val;}
		elsif ( $sec eq "Network" ){$ret[11] = $val;}
		elsif ( $sec eq "Airtime" ){$ret[12] = $val;}
		elsif ( $sec eq "Latest Episode" ){my($ep,$title,$airdate) = split('\^',$val);$ret[3] = $ep.", \"".$title."\" aired on ".$airdate;}
		elsif ( $sec eq "Episode Info" ){my($ep,$title,$airdate) = split('\^',$val);$ret[5] = $title;$ret[4] = $airdate;}
		elsif ( $sec eq "Episode URL" ){$ret[6] = $val;}
		}
	if ( $ret[0] ){return @ret;}
	else{return 0;}
	}
return 0;
}

# load config file
open(CONFIG,"tvshow-workflow.config") or die "\nCan't find config file.\n";
my %config = ();
while (<CONFIG>) {
    chomp;
    next if /^\s*\#/;
    next unless /=/;
    my ($key, $variable) = split(/\s*=\s*/,$_,2);
    $variable =~ s/(\$(\w+))/$config{$2}/g;
    $config{$key} = $variable;
}

# set variables from config file
my $AP_bin=$config{'AtomicParsleyLocation'};
my $HB_CLI_bin=$config{'HandBrakeCLILocation'};
my $iTunes_auto_import_dir=$config{'iTunesAutoImportLocation'};
my $HBPresetName=$config{'HandBrakePresetName'};
my $ProwlAPIKey=$config{'ProwlAPIKey'};

# get ip address of machine to use in lock file
my $ipaddress = `ifconfig -a | perl -ne 'if ( m/^\\s*inet (?:addr:)?([\\d.]+).*?cast/ ) { print qq(\$1\n); exit 0; }'`;

# set lockfile varible
my $lockfile = "./Staging/Locks/$ipaddress";
chomp $lockfile;

# file extensions to scan for
my $include="\'.avi|.mkv|.mp4|.m4v\'";

# clear
system("clear");

# check if HandBrake application exists before starting
die "Can't find HandBrakeCLI at $HB_CLI_bin"
    unless -e $HB_CLI_bin;

# check if AtomicParsley application exists before starting
die "Can't find AtomicParsley at $AP_bin"
    unless -e $AP_bin;

# create staging directories if they don't exist
unless (-d "./Staging") {
	mkdir "./Staging";
}

unless (-d "./Staging/Tagged") {
	mkdir "./Staging/Tagged";
}

unless (-d "./Staging/Locks") {
	mkdir "./Staging/Locks";
}

unless (-d "./Staging/Originals") {
	mkdir "./Staging/Originals";
}

unless (-d "./Staging/Imported") {
	mkdir "./Staging/Imported";
}

unless (-d "./Staging/Encoding") {
	mkdir "./Staging/Encoding";
}

# list video files and assign that list to the videolist array
my @videolist = `ls -1 | grep -Ei $include`;

if (-e $lockfile) {
	print "Script currently running on this computer.\n";
}
else {
	# check if any compatible files are found before proceeding
	if (@videolist) {
	
		open(my $fh, '>>', $lockfile) or die "Could not open '$lockfile' - $!";
		flock($fh, LOCK_EX) or die "Could not lock '$lockfile' - $!";
	
		# print list of files to be worked on and move them to the originals folder
		print "\nOriginal files:\n";
		foreach my $videofile (@videolist){
			# eat the return character at the end of the file name
			chomp $videofile;
	
			# print list of files to be worked on
			print "$videofile";
			print "\n";
	
			# move original file to Originals folder
			`mv "$videofile" ./Staging/Originals/"$videofile"`;
		}
		
		# print the HandBrake preset to be used
		print "\nHandBrake Preset: $HBPresetName\n";
		
		# main loop
		foreach my $videofile (@videolist){
			# retrieve show name and replace periods with spaces
			my $newShowName = $videofile;
			$newShowName =~ s/(^.*)(\.s\d+e\d+.*)/$1/i;
			$newShowName =~ s/\./ /g;
	
			# retrieve season and episode string
			my $seasonEpisode = $videofile;
			$seasonEpisode =~ s/(^.*\.)(s\d+e\d+)(.*)/$2/i;
	
			# check to make sure both newShowName and seasonEpisode strings exist
			# if either string is missing report an error, otherwise proceed
			if (($newShowName eq $videofile) || ($seasonEpisode eq $videofile)) {
				print "\n##########\n";
				print "ERROR: Show name and/or season and episode numbers were not found in the video file name.\n";
				print "ERROR: Video file name: ";
				print $videofile;
				print "\n";
				
				# move file out of staging folder
				`mv ./Staging/Originals/"$videofile" ./"$videofile"`;
			} 
			else {
				# retrieve season and episode numbers
				my $newSeason = $seasonEpisode;
				my $newEpisode = $seasonEpisode;
				$newSeason =~ s/s(\d+)e(\d+)/$1/i;
				$newEpisode=~ s/s(\d+)e(\d+)/$2/i;
		
				# establish show_info array with information pulled from tvrage
				my @show_info = &get_show($newShowName,"1",$newSeason."x".$newEpisode);
				
				# set episode variables
				my $TVShowName = decode_entities($show_info[0]);
				my $EpisodeName = "";
				if (defined($show_info[5])) {
					$EpisodeName = decode_entities($show_info[5]);
				}
				my $TVNetwork = $show_info[11];
				my $ShowGenre = $show_info[10];
				my $AirDate = $show_info[4];
				my $releaseDate = "";
				
				# construct release date
				if ($AirDate) {
					my $mon2num = {};
					my %mon2num = qw(
					  jan 01  feb 02  mar 03  apr 04  may 05  jun 06
					  jul 07  aug 08  sep 09  oct 10 nov 11 dec 12
					);
					my $_ = "";
					my @date = split(/\//, $show_info[4]);
					my $releaseDay = $date[0];
					my $releaseMonth = $mon2num{lc $date[1]};
					my $releaseYear = $date[2];
					$releaseDate = $releaseYear . "-" . $releaseMonth . "-" . $releaseDay . "T09:00:00Z";
				}
				
				# build new file name
				my $newFileName = $TVShowName." - S".$newSeason."E".$newEpisode.".m4v";
		
				# print show information
				print "\n##########\n";
				print "Show name: ";
				print $TVShowName;
				print "\nEpisode title: ";
				print $EpisodeName;
				print "\nNew File Name: ";
				print $newFileName;
				print "\n";
				if (defined $AirDate) {
					print "Air date: ";
					print $AirDate;
					print "\n";
				}
		
				# encode file with HandBrakeCLI
				print "\nEncoding file... (Start time: ". POSIX::strftime('%H:%M:%S', localtime).")";
				my $HBrun = `$HB_CLI_bin -i "./Staging/Originals/$videofile" -o "./Staging/Encoding/$newFileName" --preset="$HBPresetName" > /dev/null 2>&1`;
				print "\nEncoding complete. (End time: ". POSIX::strftime('%H:%M:%S', localtime).")\n";
		
				# use AtomicParsley to write the data to the file
				print "\nTagging and importing file... (Start time: ". POSIX::strftime('%H:%M:%S', localtime).")";
				my $APrun = `"$AP_bin" "./Staging/Encoding/$newFileName" --TVShowName "$TVShowName" --artist "$TVShowName" --TVEpisode "$newEpisode" --title "$EpisodeName" --TVEpisodeNum "$newEpisode" --tracknum "$newEpisode" --TVSeasonNum "$newSeason" --album "Season $newSeason" --TVNetwork "$TVNetwork" --genre "$ShowGenre" --year "$releaseDate" --stik "TV Show" -o "./Staging/Tagged/$newFileName"`;
		
				# establish final path to tagged file
				my $finalPath = cwd;
				$finalPath .= "/Staging/Tagged/$newFileName";
		
				# check if file exists before proceeding with import, move, and delete
				if (-e $finalPath) {
			
					# copy new file to Imported folder then move into iTunes import folder
					`cp ./Staging/Tagged/"$newFileName" ./Staging/Imported/"$newFileName"`;
					`mv ./Staging/Tagged/"$newFileName" "$iTunes_auto_import_dir"`;
					print "\nFile imported. (End time: ". POSIX::strftime('%H:%M:%S', localtime).")\n##########\n";
			
					# delete file in Encoding directory
					unlink("./Staging/Encoding/$newFileName");
				
					if ($ProwlAPIKey) {
						my $TVShowNameEncoded = encode_entities($TVShowName);
						my $EpisodeNameEncoded = encode_entities($EpisodeName);
						my $callProwl = get("https://prowl.weks.net/publicapi/add?apikey=$ProwlAPIKey&application=TV%20Shows&event=Import&description=$TVShowNameEncoded - S$newSeason"."E$newEpisode\n\"$EpisodeNameEncoded\"");
					}
				}
		
				else {
					print "ERROR: File not found for import into iTunes.\n";
					print "ERROR: Path to video file: ";
					print $finalPath;
					print "\n";
				}
			}
		}
		close($fh) or die "Could not write '$lockfile' - $!";
		unlink($lockfile);
	}
	else {
		print "No compatible video files found.\n";
	}
}