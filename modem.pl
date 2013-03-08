#!/usr/bin/perl

use DBI;
use DateTime;
use DateTime::Duration;
use DateTime::Format::MySQL;
use Device::Modem;
require Term::Screen;
use strict;


######## constants
use constant DB_NAME				=> "socialtelephony";
use constant DB_USER				=> "XXXX";
use constant DB_PASSWD				=> "XXXXXX";
use constant DEBUG					=> 0;
use constant COL_PADDING			=> 20;
use constant ROW_PADDING			=> 8;
use constant SHUTDOWN_HR			=> 21;
use constant SHUTDOWN_MIN			=> 5;
# durations
use constant DIALLING_DUR			=> 22;
#use constant DIALLING_DUR			=> 9;
use constant STANDARD_PAUSE			=> 0.2;
use constant AUDIO_INTRO_DUR			=> 20;
use constant AUDIO_PROMPT_DUR			=> 15;
use constant POSTCOMMENT_PROMPT_DUR		=> 11;
use constant ENTER_DTMF_DUR			=> 6;
use constant POST_ENTER_DTMP_DUR		=> 10;
use constant CALL_GAP				=> 1;
use constant MAX_CALL_LEN			=> 60;
# msgs
use constant WELCOME_MSG			=> "Tantalum Memorial";
use constant HELP_MSG				=> "press any key to stop script";
use constant WAITING_FOR_CONN			=> "Waiting for connection";
use constant NO_CONN				=> "No answer";
use constant GOT_CONN				=> "Connected";
use constant ANSWERED				=> "Answered";
use constant PLAY_INTRO				=> "Playback audio \"intro\"";
use constant PLAY_AUDIO_NAMED			=> "Playback audio ";
use constant PLAY_AUDIO_PROMPT_OPT_PASS_FIN	=> "Playback audio prompt";
use constant RECORD_COMMENT			=> "Recording comment...";
use constant RECORD_COMMENT_END			=> "...recording finished";
use constant PLAY_AUDIO_PROMPT_REQ_OPT		=> "Playback audio prompt";
use constant INPUT_DIGITS			=> "Get DTMF digits...";
use constant RECEIVED_NUM			=> "Received ";
use constant HANGUP				=> "Hangup";
use constant TIME_ZONE				=> "Europe/Rome";

######## gblobals
my $time_offset = DateTime::Duration->new(days => 1);
my $last_call_time_dialled;
my $curr_row = 0;
my $curr_col = 0;
my $thiscalltime_sofar = 0;
my $Log_file = "/home/tantalum/strowger/modem.log";

#sleep 120;

######### init DB
my $db_handle;
$db_handle = DBI->connect("DBI:mysql:".DB_NAME, DB_USER, DB_PASSWD) or die "Can't connect to db [$db_handle->errstr]\n";
$db_handle->trace(0);

######## init screen
my $scr = new Term::Screen;
unless ($scr) { die " Something's wrong w/screen \n"; }

######### init Modem
#
my @modem_ports = qw( /dev/ttyS0 /dev/ttyUSB0  /dev/ttyUSB1  /dev/ttyUSB2  /dev/ttyUSB3  /dev/ttyUSB4  /dev/ttyUSB5  /dev/ttyUSB6 );


my %modem;
foreach (@modem_ports){
		my $mod = new Device::Modem(port=>$_);
		if ( modem_connect($mod) ){
			$modem{$_}{modem} =  $mod;
			print_log("found modem $_");
		}else{
			to_screen("NO CONNECTION! for ". $_ , 1);
		}
}

sub modem_connect {

	my $modem = shift;
	my $has_modem = 0;
	if($modem->connect(baudrate=>57600)){
		to_screen("MODEM CONNECTED", 1);
		$modem->atsend('AT X0' . Device::Modem::CR);
		to_screen("SENT MODEM X0, MODEM SAYS " . $modem->answer(10), 1);
		$modem->atsend('ATS7=255' . Device::Modem::CR);
	

		to_screen("SENT MODEM TIMEOUT=255, MODEM SAYS " . $modem->answer(10), 1);
		$modem->atsend('ATM0' . Device::Modem::CR);
		to_screen("SENT MODEM TIMEOUT=255, MODEM SAYS " . $modem->answer(10), 1);
		$has_modem = 1;

	}else{
		to_screen("NO CONNECTION!", 1);
		$has_modem = 0;
	}
	return $has_modem;
}
####### setup
my $start_date = DateTime->now(time_zone=>TIME_ZONE)->subtract_duration($time_offset);
my $call_row = get_next_call($start_date);
# screen message
#$scr->at(ROW_PADDING, ($scr->cols()/2) - (length(WELCOME_MSG)/2))->puts(WELCOME_MSG);
$scr->clrscr();
#my $msg_border = '+---------------------------------------------------------------------------+';
#$scr->at(ROW_PADDING + 1, ($scr->cols()/2) - (length($msg_border)/2))->puts($msg_border);

$curr_row = ROW_PADDING;
#$curr_row = ROW_PADDING + 2;
#for(0..500){

#	foreach( keys %modem){
				
			#	my $st = "ATDP99";
			#	$modem{$_}{modem}->atsend($st . Device::Modem::CR );
			#	to_screen("$_ Dialling " . $st );
			#	sleep 1;
			
	#	}
#	foreach(keys %modem) {
	#	$modem{$_}{modem}->hangup();
#	}
#	sleep 3;
#}

#die;
####### main loop

while(1){ 
	$thiscalltime_sofar = 0;
	my $call_time_dialled;
	eval{$call_time_dialled = DateTime::Format::MySQL->parse_datetime($call_row->{timeDialled});};
	my $call_time_finished;
	eval{$call_time_finished = DateTime::Format::MySQL->parse_datetime($call_row->{timeFinished});};
	
	if(!$call_time_dialled or !$call_time_finished){
		# we had an error pulling out datetimes for this row. Try 10 minutes later...
		to_screen("Error with timeDialled or timeFinished", 1);
		$time_offset += DateTime::Duration->new(minutes => 10); # changing time offset for future reference
		$call_row = get_next_call(DateTime->now(time_zone=>TIME_ZONE)->subtract_duration($time_offset));
		next;
	}
	$call_time_dialled->set_time_zone(TIME_ZONE);
	$call_time_finished->set_time_zone(TIME_ZONE);

	my $pre_call_pause = $call_time_dialled->subtract_datetime_absolute(DateTime->now(time_zone=>TIME_ZONE)->subtract_duration($time_offset));
	my $pre_call_seconds = $pre_call_pause->in_units('seconds');

	if(!$last_call_time_dialled){
		$last_call_time_dialled = $call_time_dialled;
		# since this is the first run - we will adjust time_offset up to the next record
		$time_offset -= DateTime::Duration->new(seconds => $pre_call_seconds);
		$pre_call_seconds = 0;
	}else{
		to_screen("Waiting standard " . CALL_GAP . " second till next call, net timeDialled = $call_time_dialled", 1);
		sleep_lightly(CALL_GAP); # this means time_offset is no longer accurate
	}

	#
	# make call, if call not answered, wait untill the end of call and hangup
	#
	call_switches($call_row->{tUserPhoneNumber}, $call_row->{tCallID});
	sleep_lightly(DIALLING_DUR); #  seconds for dialing
	my	$pause_till_call_end = $call_time_finished->subtract_datetime_absolute($call_time_dialled)->in_units('seconds');	
	$pause_till_call_end -= DIALLING_DUR;
	$pause_till_call_end = MAX_CALL_LEN unless $pause_till_call_end < MAX_CALL_LEN;
	$pause_till_call_end = STANDARD_PAUSE unless $pause_till_call_end > STANDARD_PAUSE;
	my $wait_answer = 2 + int(rand(7));
	if(!$call_row->{wasAnswered}){
		to_screen(GOT_CONN);
		sleep_lightly($wait_answer);
		#to_screen(WAITING_FOR_CONN);
		to_screen("Call unanswered, waiting $pause_till_call_end till call end. Started at $call_time_dialled, finished at $call_time_finished", 1);
		#sleep_lightly($pause_till_call_end);
		to_screen(NO_CONN);
		sleep_lightly(STANDARD_PAUSE);
	}else{
		to_screen(GOT_CONN);
		sleep_lightly($wait_answer);
		to_screen(ANSWERED);
		sleep_lightly(STANDARD_PAUSE);
		to_screen(PLAY_INTRO); 

		if(!$call_row->{wasScriptPlayed}){
			# just pause for whole call duration then finsh
			$pause_till_call_end -= $wait_answer - STANDARD_PAUSE;
			$pause_till_call_end = STANDARD_PAUSE unless $pause_till_call_end > STANDARD_PAUSE;
			to_screen("Script wasn't played, waiting $pause_till_call_end seconds till end of call", 1);
			sleep_lightly($pause_till_call_end);
		}else{
			sleep_lightly(AUDIO_INTRO_DUR);
			my $ScriptName = $call_row->{tScriptName};
			$ScriptName =~ s/^\d+_//;			# RQW: strip off any numerical prefix
			to_screen(PLAY_AUDIO_NAMED . "\"" . $ScriptName . "\""); 
			#!!!!!
			# tScriptDuration is NULL right now, so we're just using a test value
			sleep_lightly(60);
			to_screen(PLAY_AUDIO_PROMPT_OPT_PASS_FIN);
			to_screen(PLAY_AUDIO_PROMPT_OPT_PASS_FIN . "** Option comment, pass, or finish", 1);
			sleep_lightly(AUDIO_PROMPT_DUR);
			my $forwarded_script = $call_row->{nextCallID} != undef;
			my $err_call_fw = $call_row->{errorCallFW};
			to_screen("Error call fw = $err_call_fw", 1);

			if($call_row->{commentID} != -1){
				to_screen(RECORD_COMMENT);
				#!!!!!
				# commentDuration is NULL right now, using testing value
				sleep_lightly(60);
				to_screen(RECORD_COMMENT_END);
				if($forwarded_script){
					to_screen(PLAY_AUDIO_PROMPT_REQ_OPT); # requesting option
					to_screen(PLAY_AUDIO_PROMPT_REQ_OPT . "** Option pass or finish", 1);
					sleep_lightly(POSTCOMMENT_PROMPT_DUR); # record transfer
				}
			}
			if($forwarded_script or $err_call_fw){
				to_screen(INPUT_DIGITS);
				sleep_lightly(ENTER_DTMF_DUR); # transfer extension
				if($forwarded_script){
					my $next_number = get_ph_by_id($call_row->{nextCallID});
					if(!defined($next_number)){
						$next_number = 'xxxx';
					}
					to_screen(RECEIVED_NUM . $next_number);
				}
				sleep_lightly(POST_ENTER_DTMP_DUR);
			}
			# whatever the difference is between this point, and the end of the call
			# we'll just wait it out
			$pause_till_call_end = $call_time_finished->subtract_datetime_absolute(DateTime->now(time_zone=>TIME_ZONE))->in_units('seconds');	
			if($pause_till_call_end > 0){
				$pause_till_call_end = MAX_CALL_LEN unless $pause_till_call_end < MAX_CALL_LEN;
				to_screen("$pause_till_call_end seconds till the end of this call..", 1);
				sleep_lightly($pause_till_call_end); 
			}
		}
	}
	#
	# Hang up, and set $call_row to the next call record
	#
	to_screen(HANGUP);
	foreach( keys %modem){
		$modem{$_}{modem}->hangup();
		print_log("hungup $_");	
	}	
	
# 	$scr->clrscr();
	$call_row = get_next_call($call_time_finished); 
	$curr_row += 2;
}

sub do_hangup {
	to_screen(HANGUP);
	foreach( keys %modem){
		$modem{$_}{modem}->hangup();
print_log("hungup $_");	
	}
}

####### subroutines
sub get_next_call {
	my $last_dt = shift;
	my $sth = prep_main_select($last_dt);
	$sth->execute();
	while($sth->rows == 0){
		# must have got to the end of the records... loop back using start_date
		to_screen("No more rows in tCall, jump back one day", 1);
		sleep_lightly(STANDARD_PAUSE);
		$sth = prep_main_select($last_dt->subtract_duration(DateTime::Duration->new(days => 1)));
		$sth->execute();
	}
	return $sth->fetchrow_hashref();
}

sub prep_main_select{
	my $dt = shift;
	return $db_handle->prepare("
		SELECT tCall.tCallID, tCall.timeDialled, tCall.timeFinished, tCall.wasAnswered, 
			tCall.wasScriptPlayed, tCall.commentID, tCall.nextCallID, tCall.errorCallFW,
			phone.tUserPhoneNumber, scrpt.tScriptName 
		FROM tCall
		INNER JOIN tUserPhone phone ON tCall.calledNumberID = phone.tUserPhoneID 
		LEFT OUTER JOIN tScript scrpt ON tCall.playedScriptID = scrpt.tScriptID 
		LEFT OUTER JOIN tComment comm ON tCall.commentID = comm.tCommentID 
		WHERE tCall.timeDialled > '" . DateTime::Format::MySQL->format_datetime($dt) . "' 
		ORDER BY tCall.timeDialled LIMIT 1;");
}

sub get_ph_by_id {
	# this returns a phone number just for display purposes
	my $tup_id = shift;
	my $sth = $db_handle->prepare("SELECT tUserPhone.tUserPhoneNumber FROM tUserPhone, tCall 
					WHERE tCall.tCallID = $tup_id AND tUserPhone.tUserPhoneID = tCall.calledNumberID;");
	$sth->execute();
	if($sth->rows != 1){
		return undef;
	}
	my $n = $sth->fetchrow_hashref()->{tUserPhoneNumber};
	$n =~ s/[^\d]//g; # strip out non-numbers
	return $n;
	return display_phone_num($n);
}

sub display_phone_num{
	my $num = shift;
	return substr($num, 0, length($num) - 4) . "XXXX";
}

sub call_switches {
	my $ph_number = shift;
	my $tcallid = shift;
	to_screen("Dialling $ph_number, tCallID = $tcallid", 1);
	$ph_number =~ s/[^\d]//g; # strip out non numbers
	my $display_ph_number = display_phone_num($ph_number);
	#if(length($ph_number) > 7){
		#$ph_number = substr($ph_number, length($ph_number) - 7);
	#	$ph_number = substr($ph_number, length($ph_number) - 6);
	#}
	to_screen("Dialling $display_ph_number ");
#	die;
	$ph_number =~ /(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)/;
	
	my @digits;
	$digits[0] = [$2,$3];
	$digits[1] = [$4,$5];
	$digits[2] = [$6,$7];
	$digits[3] = [$8,$9];
	$digits[4] = [$10,$11];
	
#die $digits[4][0];


#	for(my $cnt = 0; $cnt <= $#digits;$cnt++){ 
#		$digits[$cnt] .= "ATDP".$digits[$cnt];
#			to_screen("Dialling " . $digits[$cnt]);
#	}
	# if digits /2 is greater then the number of modems
	# assign 2 digits to each modem
	my $more_mods_then_digits = 0;
	my $inc = scalar @digits  / scalar (keys %modem);
	#die $inc;

		#put two digits in each modem.
		#if(DEBUG){	to_screen(" We have more digits then modems", 1); }
	my $cnt = 0;
	foreach( keys %modem){
		@{$modem{$_}{dig}} = ($digits[int($cnt)][0],$digits[int($cnt)][1]);

		$cnt+= $inc;
	}
	
	foreach my $i (0..1){
		foreach( keys %modem){
				my @ar = @{ $modem{$_}{dig} };
				my $st = "ATDP" . $ar[$i];
				$modem{$_}{modem}->atsend($st . Device::Modem::CR );
			#	to_screen("$_ Dialling " . $st );
				sleep 1.5;
				$thiscalltime_sofar += 1.5;
				#$modem{$_}->atsend($digits[$cnt + 1] . Device::Modem::CR);
		}
	
	}

	

}

sub to_screen{
	my $msg = shift;
	my $debug = shift;
#$scr->clrscr();
	if($curr_row > ($scr->rows() - ROW_PADDING)){
		my $row_diff = $scr->rows() - ROW_PADDING - $curr_row;
		while($row_diff < 1){
			$scr->at(ROW_PADDING, 0)->dl();
			$curr_row --;
			$row_diff ++;
		}
	}

	if($debug){
		if(DEBUG){
		$scr->reverse();
		$scr->at(ROW_PADDING, COL_PADDING)->clreol()->puts($msg);
		$scr->normal();
		}
	}else{
		$curr_col = length($msg);
		$scr->at($curr_row, COL_PADDING)->puts($msg)->at($curr_row, $scr->cols());
		$curr_row += 1;
	}

}

sub sleep_lightly{
	# sleeps one second at a time and checks for quit
	my $secs = shift;
if (DEBUG) {to_screen(" secs " .$secs,1)};
	sleep($secs);
	my $now = DateTime->now(time_zone=>TIME_ZONE);
	if($now->hour >= SHUTDOWN_HR && $now->minute >= SHUTDOWN_MIN){
		exit 0;
	}
	#while($secs > 0){
		#$c = $scr->getch();
		#if(ord($c) == 20){
		#if($scr->key_pressed()){
			#$scr->flush_input();
			#$scr->clrscr();
			#exit 0;
		#}
		#sleep(0.5);
		#$secs -= 0.5;
		## check for shutdown time
	#}
	$thiscalltime_sofar += $secs;
	
}

###### testing subroutines
sub get_testing_offset {
	# return a duration object that is 10 seconds before earliest record in tCall...
	my $sth = $db_handle->prepare('SELECT timeDialled FROM tCall ORDER BY timeDialled LIMIT 1;');
	$sth->execute();
	my $row = $sth->fetchrow_hashref();
	$sth->finish;
	my $first_dt = DateTime::Format::MySQL->parse_datetime($row->{timeDialled});
	return (DateTime->now(time_zone=>TIME_ZONE) - $first_dt) + DateTime::Duration->new(seconds=>10);
}

sub dump_tbl {
	my $tbl = shift;
	my $sth = $db_handle->prepare("SELECT * FROM $tbl;");
	$sth->execute();
	DBI::dump_results($sth) or die "d'oh [$DBI::errstr]\n";
	$sth->finish;
}

sub print_log {
	my ($msg) = @_;

	open LOG, ">> $Log_file" or die "Cant create log file $Log_file: $!"; 
	print LOG localtime(time)." ".$msg."\n";
	close LOG;
}

$db_handle->disconnect;
exit;

