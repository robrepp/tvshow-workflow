#!/usr/bin/perl -w
use strict;

# get_show function authored by tvrage.com
# available at http://tvrage.com/info/quickinfo.html
use LWP::Simple;
sub get_show {
my ($show) = $_[0];
my ($exact ) = $_[1];
my ($episode) = $_[2];
my @ret = "";
if ( $show ne "" ){
	my $site = get "http://www.tvrage.com/quickinfo.php?show=".$show."&ep=".$episode."&exact=".$exact;
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

# set variables
my $AP_bin="/usr/bin/AtomicParsley";
my $include="\'.mp4|.m4a|.m4b|.m4p|.m4v|.3gp|.3g2\'";

# list video files and assign that list to the videolist array
my @videolist = `ls -1 | grep -Ei $include`;

# main loop
foreach my $videofile (@videolist){
	
	# eat the return character at the end of the file name
	chomp $videofile;
	
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
	} 
	else {
		
		# retrieve season and episode numbers
		my $newSeason = $seasonEpisode;
		my $newEpisode = $seasonEpisode;
		$newSeason =~ s/s(\d+)e(\d+)/$1/i;
		$newEpisode=~ s/s(\d+)e(\d+)/$2/i;
		
		# establish show_info array with information pulled from tvrage
		my @show_info = &get_show($newShowName,"1",$newSeason."x".$newEpisode);
		
		# build new file name
		my $newFileName = $newShowName." S".$newSeason." E".$newEpisode.".m4v";
		
		# print show information
		print "\n##########\n";
		print "Show name: ";
		print $newShowName;
		print "\nEpisode title: ";
		print $show_info[5];
		print "\nNew File Name: ";
		print $newFileName;
		print "\n";
		
		# use AtomicParsley to write the data to the file
		my $APrun = `"$AP_bin" "$videofile" --TVShowName "$show_info[0]" --artist "$show_info[0]" --TVEpisode "$newEpisode" --title "$show_info[5]" --TVEpisodeNum "$newEpisode" --tracknum "$newEpisode" --TVSeasonNum "$newSeason" --album "Season $newSeason" --TVNetwork "$show_info[11]" --genre "$show_info[10]" --stik "TV Show" -o "./Completed/$newFileName"`;
		
		# establish final path to tagged file for Applescript
		my $finalPath = `pwd`;
		chomp $finalPath;
		$finalPath .= "/Completed/$newFileName";
		
		# check if file exists before proceeding with import, move, and delete
		if (-e $finalPath) {

		# import into iTunes
		`osascript -e 'tell application "iTunes" to activate'`;
		`osascript -e 'tell application "iTunes" to add (POSIX file "$finalPath")'`;
		
		# move new file to Imported folder
		`mv ./Completed/"$newFileName" ./Completed/Imported/"$newFileName"`;
		
		# move original file to Originals folder
		`mv "$videofile" ./Completed/Originals/"$videofile"`;
		}
		
		else {
			print "ERROR: File not found for import into iTunes.\n";
			print "ERROR: Path to video file: ";
			print $finalPath;
			print "\n";
		}
	}
}