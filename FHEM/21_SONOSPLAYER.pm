########################################################################################
#
#  SONOSPLAYER.pm (c) by Reiner Leins, 2013
#  rleins at lmsoft dot de
#
#  $Id$
#
#  FHEM module to work with Sonos-Zoneplayers
#
#  Version 2.4 - December, 2013
#
#  define <name> SONOSPLAYER <UDN>
#
#  where <name> may be replaced by any name string 
#        <udn> is the Zoneplayer Identification
#
########################################################################################
# Changelog
#
# ab 2.2 Changelog nur noch in der Datei 00_SONOS
#
# 2.1:	Neuen Befehl 'CurrentPlaylist' eingeführt
#
# 2.0:	Neue Konzeptbasis eingebaut
#		Man kann Gruppen auf- und wieder abbauen
#		PlayURI kann nun einen Devicenamen entgegennehmen, und spielt dann den AV-Eingang des angegebenen Raumes ab
#		Alle Steuerbefehle werden automatisch an den jeweiligen Gruppenkoordinator gesendet, sodass die Abspielanweisungen immer korrekt durchgeführt werden
#		Es gibt neue Lautstärke- und Mute-Einstellungen für Gruppen ingesamt
#
# 1.12:	TrackURI hinzugefügt
#		Alarmbenutzung hinzugefügt
#		Schlummerzeit hinzugefügt (Reading SleepTimer)
#		DailyIndexRefreshTime hinzugefügt
#
# 1.11:	Shuffle, Repeat und CrossfadeMode können nun gesetzt und abgefragt werden
#
# 1.10:	LastAction-Readings werden nun nach eigener Konvention am Anfang groß geschrieben. Damit werden 'interne Variablen' von den Informations-Readings durch Groß/Kleinschreibung unterschieden
#		Volume, Balance und HeadphonConnected können nun auch in InfoSummarize und StateVariable verwendet werden. Damit sind dies momentan die einzigen 'interne Variablen', die dort verwendet werden können
#		Attribut 'generateVolumeEvent' eingeführt.
#		Getter und Setter 'Balance' eingeführt.
#		Reading 'HeadphoneConnected' eingeführt.
#		Reading 'Mute' eingeführt.
#		InfoSummarize-Features erweitert: 'instead' und 'emptyval' hinzugefügt
#
# 1.9:	
#
# 1.8:	minVolume und maxVolume eingeführt. Damit kann nun der Lautstärkeregelbereich der ZonePlayer festgelegt werden
#
# 1.7:	Fehlermeldung bei aktivem TempPlaying und damit Abbruch der Anforderung deutlicher geschrieben
#
# 1.6:	Speak hinzugefügt
#
# Versionsnummer zu 00_SONOS angeglichen
#
# 1.3:	Zusätzliche Befehle hinzugefügt
#
# 1.2:	Einrückungen im Code korrigiert
#
# 1.1: 	generateInfoAnswerOnSet eingeführt (siehe Doku im Wiki)
#		generateVolumeSlider eingeführt (siehe Doku im Wiki)
#
# 1.0:	Initial Release
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
########################################################################################
# Uses Declarations
########################################################################################
package main;

use vars qw{%attr %defs};
use strict;
use warnings;
use URI::Escape;
use Thread::Queue;

require 'HttpUtils.pm';

sub Log($$);
sub Log3($$$);
sub SONOSPLAYER_Log($$$);

########################################################################################
# Variable Definitions
########################################################################################
my %gets = (
	'CurrentTrackPosition' => '',
	'Playlists' => '',
	'Favourites' => '',
	'Radios' => '',
	'Alarm' => 'ID',
	'EthernetPortStatus' => 'PortNum'
);

my %sets = (
	'Play' => '',
	'Pause' => '',
	'Stop' => '',
	'Next' => '',
	'Previous' => '',
	'LoadPlaylist' => 'playlistname',
	'SavePlaylist' => 'playlistname',
	'CurrentPlaylist' => '',
	'EmptyPlaylist' => '',
	'StartFavourite' => 'favouritename',
	'CreateThemeList' => 'searchField=searchValue',
	'LoadRadio' => 'radioname',
	'PlayURI' => 'songURI',
	'PlayURITemp' => 'songURI',
	'AddURIToQueue' => 'songURI',
	'Speak' => 'volume language text',
	'Mute' => 'state',
	'Shuffle' => 'state',
	'Repeat' => 'state',
	'CrossfadeMode' => 'state',
	'LEDState' => 'state',
	'MuteT' => '',
	'VolumeD' => '',
	'VolumeU' => '',
	'Volume' => 'volumelevel',
	'VolumeSave' => 'volumelevel',
	'VolumeRestore' => '',
	'Balance' => 'balancevalue',
	'Loudness' => 'state',
	'Bass' => 'basslevel',
	'Treble' => 'treblelevel',	
	'CurrentTrackPosition' => 'timeposition',
	'Track' => 'tracknumber|Random',
	'Alarm' => 'create|update|delete ID valueHash',
	'DailyIndexRefreshTime' => 'timestamp',
	'SleepTimer' => 'time',
	'AddMember' => 'member_devicename',
	'RemoveMember' => 'member_devicename',
	'GroupVolume' => 'volumelevel',
	'GroupMute' => 'state',
	'Reboot' => '',
	'Wifi' => 'state'
);

########################################################################################
#
#  SONOSPLAYER_Initialize
#
#  Parameter hash = hash of device addressed
#
########################################################################################
sub SONOSPLAYER_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "SONOSPLAYER_Define";
  $hash->{UndefFn} = "SONOSPLAYER_Undef";
  $hash->{GetFn}   = "SONOSPLAYER_Get";
  $hash->{SetFn}   = "SONOSPLAYER_Set";
  $hash->{StateFn} = "SONOSPLAYER_State";

  $hash->{AttrList}= "disable:0,1 generateVolumeSlider:0,1 generateVolumeEvent:0,1 generateSomethingChangedEvent:0,1 generateInfoSummarize1 generateInfoSummarize2 generateInfoSummarize3 generateInfoSummarize4 stateVariable:TransportState,NumberOfTracks,Track,TrackURI,TrackDuration,Title,Artist,Album,OriginalTrackNumber,AlbumArtist,Sender,SenderCurrent,SenderInfo,StreamAudio,NormalAudio,AlbumArtURI,nextTrackDuration,nextTrackURI,nextAlbumArtURI,nextTitle,nextArtist,nextAlbum,nextAlbumArtist,nextOriginalTrackNumber,Volume,Mute,Shuffle,Repeat,CrossfadeMode,Balance,HeadphoneConnected,SleepTimer,Presence,RoomName,SaveRoomName,PlayerType,Location,SoftwareRevision,SerialNum,InfoSummarize1,InfoSummarize2,InfoSummarize3,InfoSummarize4 model minVolume maxVolume minVolumeHeadphone maxVolumeHeadphone VolumeStep getAlarms:0,1 buttonEvents";
  
  return undef;
}
  
########################################################################################
#
#  SONOSPLAYER_Define - Implements DefFn function
# 
#  Parameter hash = hash of device addressed, def = definition string
#
########################################################################################
sub SONOSPLAYER_Define ($$) {
	my ($hash, $def) = @_;
  
	# define <name> SONOSPLAYER <udn>
	# e.g.: define Sonos_Wohnzimmer SONOSPLAYER RINCON_000EFEFEFEF401400
	my @a = split("[ \t]+", $def);
  
	my ($name, $udn);
  
	# default
	$name = $a[0];
	$udn = $a[2];

	# check syntax
	return "SONOSPLAYER: Wrong syntax, must be define <name> SONOSPLAYER <udn>" if(int(@a) < 3);
  
	readingsSingleUpdate($hash, "state", 'init', 1);
	readingsSingleUpdate($hash, "presence", 'disappeared', 0); # Grund-Initialisierung, falls der Player sich nicht zurückmelden sollte...
	
	$hash->{UDN} = $udn;
	readingsSingleUpdate($hash, "state", 'initialized', 1);
	
	return undef; 
}

#######################################################################################
#
#  SONOSPLAYER_State - StateFn, used for deleting unused or initialized Readings...
#
########################################################################################
sub SONOSPLAYER_State($$$$) {
	my ($hash, $time, $name, $value) = @_;
	
	# Die folgenden Readings müssen immer neu initialisiert verwendet werden, und dürfen nicht aus dem Statefile verwendet werden
	return 'Reading '.$hash->{NAME}."->$name not used out of statefile." if ($name eq 'presence') || ($name eq 'LastActionResult');
	
	# Die folgenden Readings werden nicht mehr benötigt, und werden hiermit entfernt...
	return 'Reading '.$hash->{NAME}."->$name unused and deleted for all Zoneplayer-Types." if ($name eq 'LastGetActionName') || ($name eq 'LastGetActionResult') || ($name eq 'LastSetActionName') || ($name eq 'LastSetActionResult') || ($name eq 'LastSubscriptionsRenew') || ($name eq 'LastSubscriptionsResult') || ($name eq 'SetMakeStandaloneGroup') || ($name eq 'CurrentTempPlaying') || ($name eq 'SetWRONG');
	
	# Wenn es eine Bridge ist, noch zusätzliche, überflüssige, Readings entfernen
	if ((uc(ReadingsVal($hash->{NAME}, 'playerType', '')) eq 'ZB100') || (AttrVal($hash, 'model', '') =~ m/ZB100/i)) {
		return 'Reading '.$hash->{NAME}."->$name unused and deleted for Bridges." if ($name eq 'AlarmList') || ($name eq 'AlarmListIDs') || ($name eq 'AlarmListVersion');
	}
	
	return undef;
}

########################################################################################
#
#  SONOSPLAYER_Get - Implements GetFn function 
#
#  Parameter hash = hash of device addressed
#						 a = argument array
#
########################################################################################
sub SONOSPLAYER_Get($@) {
	my ($hash, @a) = @_;
	
	my $reading = $a[1];
	my $name = $hash->{NAME};
	my $udn = $hash->{UDN}; 
	
	# check argument
	return "SONOSPLAYER: Get with unknown argument $a[1], choose one of ".join(" ", sort keys %gets) if(!defined($gets{$reading}));
	
	# some argument needs parameter(s), some not
	return "SONOSPLAYER: $a[1] needs parameter(s): ".$gets{$a[1]} if (scalar(split(',', $gets{$a[1]})) > scalar(@a) - 2);
	
	# getter
	if (lc($reading) eq 'currenttrackposition') {
		SONOS_DoWork($udn, 'getCurrentTrackPosition');
	} elsif (lc($reading) eq 'playlists') {
		SONOS_DoWork($udn, 'getPlaylists');
	} elsif (lc($reading) eq 'favourites') {
		SONOS_DoWork($udn, 'getFavourites');
	} elsif (lc($reading) eq 'radios') {
		SONOS_DoWork($udn, 'getRadios');
	} elsif (lc($reading) eq 'ethernetportstatus') {
		my $portNum = $a[2];
		
		readingsSingleUpdate($hash, 'LastActionResult', 'Portstatus properly returned', 1);
	
		my $url = ReadingsVal($name, 'location', '');
		$url =~ s/(^http:\/\/.*?)\/.*/$1\/status\/enetports/;
		
		my $statusPage = GetFileFromURL($url);
		return (($1 == 0) ? 'Inactive' : 'Active') if ($statusPage =~ m/<Port port='$portNum'><Link>(\d+)<\/Link><Speed>.*?<\/Speed><\/Port>/i);
		return 'Inactive';
	} elsif (lc($reading) eq 'alarm') {
		my $id = $a[2];
		
		readingsSingleUpdate($hash, 'LastActionResult', 'Alarm-Hash properly returned', 1);
		
		my @idList = split(',', ReadingsVal($name, 'AlarmListIDs', ''));
		if (!SONOS_isInList($id, @idList)) {
			return {};
		} else {
			return eval(ReadingsVal($name, 'AlarmList', ()))->{$id};
		}
	}
  
	return undef;
}

#######################################################################################
#
#  SONOSPLAYER_Set - Set one value for device
#
#  Parameter hash = hash of device addressed
#            a = argument string
#
########################################################################################
sub SONOSPLAYER_Set($@) {
	my ($hash, @a) = @_;
	
	# for the ?-selector: which values are possible
	if($a[1] eq '?') {
		# %setCopy enthält eine Kopie von %sets, da für eine ?-Anfrage u.U. ein Slider zurückgegeben werden muss...
		my %setcopy;
		if (AttrVal($hash, 'generateVolumeSlider', 1) == 1) {
			foreach my $key (keys %sets) {
				my $oldkey = $key;
				$key = $key.':slider,0,1,100' if ($key eq 'Volume');
				$key = $key.':slider,-100,1,100' if ($key eq 'Balance');
			
				$setcopy{$key} = $sets{$oldkey};
			}
		} else {
			%setcopy = %sets;
		}
		
		my $sonosDev = SONOS_getDeviceDefHash(undef);
		$sets{Speak1} = 'volume language text' if (AttrVal($sonosDev->{NAME}, 'Speak1', '') ne '');
		$sets{Speak2} = 'volume language text' if (AttrVal($sonosDev->{NAME}, 'Speak2', '') ne '');
		$sets{Speak3} = 'volume language text' if (AttrVal($sonosDev->{NAME}, 'Speak3', '') ne '');
		$sets{Speak4} = 'volume language text' if (AttrVal($sonosDev->{NAME}, 'Speak4', '') ne '');
	
		return join(" ", sort keys %setcopy);
	}
	
	# check argument
	return "SONOSPLAYER: Set with unknown argument $a[1], choose one of ".join(" ", sort keys %sets) if(!defined($sets{$a[1]}));
  
	# some argument needs parameter(s), some not
	return "SONOSPLAYER: $a[1] needs parameter(s): ".$sets{$a[1]} if (scalar(split(',', $sets{$a[1]})) > scalar(@a) - 2);
      
	# define vars
	my $key = $a[1];
	my $value = $a[2];
	my $value2 = $a[3];
	my $name = $hash->{NAME};
	my $udn = $hash->{UDN};
	
	# setter
	if (lc($key) eq 'currenttrackposition') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setCurrentTrackPosition', $value);
	} elsif (lc($key) eq 'groupvolume') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		if ($value =~ m/^[+-]{1}/) {
			SONOS_DoWork($udn, 'setRelativeGroupVolume',  $value);
		} else {
			SONOS_DoWork($udn, 'setGroupVolume', $value);
		}
	} elsif (lc($key) eq 'volume') {
		if ($value =~ m/^[+-]{1}/) {
			SONOS_DoWork($udn, 'setRelativeVolume',  $value, $value2);
		} else {
			SONOS_DoWork($udn, 'setVolume', $value, $value2);
		}
	} elsif (lc($key) eq 'volumesave') {
		setReadingsVal($hash, 'VolumeStore', ReadingsVal($name, 'Volume', 0), TimeNow());
		if ($value =~ m/^[+-]{1}/) {
			SONOS_DoWork($udn, 'setRelativeVolume',  $value);
		} else {
			SONOS_DoWork($udn, 'setVolume', $value);
		}
	} elsif (lc($key) eq 'volumerestore') {
		SONOS_DoWork($udn, 'setVolume', ReadingsVal($name, 'VolumeStore', 0));
	} elsif (lc($key) eq 'volumed') {
		SONOS_DoWork($udn, 'setRelativeVolume', -AttrVal($hash->{NAME}, 'VolumeStep', 7));
	} elsif (lc($key) eq 'volumeu') {
		SONOS_DoWork($udn, 'setRelativeVolume', AttrVal($hash->{NAME}, 'VolumeStep', 7));
	} elsif (lc($key) eq 'balance') {
		SONOS_DoWork($udn, 'setBalance', $value);
	} elsif (lc($key) eq 'loudness') {
		SONOS_DoWork($udn, 'setLoudness', $value);
	} elsif (lc($key) eq 'bass') {
		SONOS_DoWork($udn, 'setBass', $value);
	} elsif (lc($key) eq 'treble') {
		SONOS_DoWork($udn, 'setTreble', $value);
	} elsif (lc($key) eq 'groupmute') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setGroupMute', $value);
	} elsif (lc($key) eq 'mute') {
		SONOS_DoWork($udn, 'setMute', $value);
	} elsif (lc($key) eq 'mutet') {
		SONOS_DoWork($udn, 'setMuteT', '');
	} elsif (lc($key) eq 'shuffle') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setShuffle', $value);
	} elsif (lc($key) eq 'repeat') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setRepeat', $value);
	} elsif (lc($key) eq 'crossfademode') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setCrossfadeMode', $value);
	} elsif (lc($key) eq 'ledstate') {
		SONOS_DoWork($udn, 'setLEDState', $value);
	} elsif (lc($key) eq 'play') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'play');
	} elsif (lc($key) eq 'stop') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'stop');
	} elsif (lc($key) eq 'pause') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'pause');
	} elsif (lc($key) eq 'previous') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'previous');
	} elsif (lc($key) eq 'next') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'next');
	} elsif (lc($key) eq 'track') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setTrack', $value);
	} elsif (lc($key) eq 'loadradio') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'loadRadio', $value);
	} elsif (lc($key) eq 'startfavourite') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'startFavourite', $value, $value2);
	} elsif (lc($key) eq 'loadplaylist') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		$value2 = 1 if (!defined($value2));
		
		if ($value =~ m/^file:(.*)/) {
			SONOS_DoWork($udn, 'loadPlaylist', ':m3ufile:'.$1, $value2);
		} else {
			SONOS_DoWork($udn, 'loadPlaylist', $value, $value2);
		}
	} elsif (lc($key) eq 'emptyplaylist') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'emptyPlaylist');
	} elsif (lc($key) eq 'saveplaylist') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		if ($value =~ m/^file:(.*)/) {
			SONOS_DoWork($udn, 'savePlaylist', $1, ':m3ufile:');
		} else {
			SONOS_DoWork($udn, 'savePlaylist', $value, '');
		}
	} elsif (lc($key) eq 'currentplaylist') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setToCurrentPlaylist');
	} elsif (lc($key) eq 'createthemelist') {
		SONOS_DoWork($udn, 'createThemelist');
	} elsif (lc($key) eq 'playuri') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		# Prüfen, ob ein Sonosplayer-Device angegeben wurde, dann diesen AV Eingang als Quelle wählen
		# TODO: Wenn dieses Quell-Device eine Playbar ist, dann den optischen Eingang als Quelle wählen...
		my $dHash = SONOS_getDeviceDefHash($value);
		if ($dHash) {
			my $udnShort = $1 if ($dHash->{UDN} =~ m/(.*)_MR/);
			$value = 'x-rincon-stream:'.$udnShort;
			# $value = 'x-sonos-htastream:'.$udnShort.':spdif';
		}
	
		SONOS_DoWork($udn, 'playURI', $value, $value2);
	} elsif (lc($key) eq 'playuritemp') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		SONOS_DoWork($udn, 'playURITemp', $value, $value2); 
	} elsif (lc($key) eq 'adduritoqueue') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'addURIToQueue', $value);
	} elsif ((lc($key) eq 'speak') || ($key =~ m/speak\d+/i)) {
		$key = 'speak0' if (lc($key) eq 'speak');
		
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		# Hier die komplette restliche Zeile in den zweiten Parameter packen, da damit auch Leerzeichen möglich sind
		my $text = '';
		for(my $i = 4; $i < @a; $i++) {
			$text .= ' '.$a[$i];
		}
		SONOS_DoWork($udn, lc($key), $value, $value2, $text);
	} elsif (lc($key) eq 'alarm') {
		# Hier die komplette restliche Zeile in den zweiten Parameter packen, da damit auch Leerzeichen möglich sind
		my $text = '';
		for(my $i = 4; $i < @a; $i++) {
			$text .= ' '.$a[$i];
		}
		
		SONOS_DoWork($udn, 'setAlarm', $value, $value2, $text);
	} elsif (lc($key) eq 'dailyindexrefreshtime') {
		SONOS_DoWork($udn, 'setDailyIndexRefreshTime', $value);
	} elsif (lc($key) eq 'sleeptimer') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		SONOS_DoWork($udn, 'setSleepTimer', $value);
	} elsif (lc($key) eq 'addmember') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		my $cHash = SONOS_getDeviceDefHash($value);
		SONOS_DoWork($udn, 'addMember', $cHash->{UDN});
	} elsif (lc($key) eq 'removemember') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		my $cHash = SONOS_getDeviceDefHash($value);
		SONOS_DoWork($udn, 'removeMember', $cHash->{UDN});
	} elsif (lc($key) eq 'reboot') {
		readingsSingleUpdate($hash, 'LastActionResult', 'Reboot properly initiated', 1);
	
		my $url = ReadingsVal($name, 'location', '');
		$url =~ s/(^http:\/\/.*?)\/.*/$1\/reboot/;
		
		GetFileFromURL($url);
	} elsif (lc($key) eq 'wifi') {
		$value = lc($value);
		if ($value ne 'on' && $value ne 'off' && $value ne 'persist-off') {
			readingsSingleUpdate($hash, 'LastActionResult', 'Wrong parameter "'.$value.'". Use one of "off", "persist-off" or "on".', 1);
			
			return undef;
		}
		
		readingsSingleUpdate($hash, 'LastActionResult', 'WiFi properly set to '.$value, 1);
		
		my $url = ReadingsVal($name, 'location', '');
		$url =~ s/(^http:\/\/.*?)\/.*/$1\/wifictrl?wifi=$value/;
		
		GetFileFromURL($url);
	} else {
		return 'Not implemented yet!';
	}
	
	return undef;
}

########################################################################################
#
#  SONOSPLAYER_GetRealTargetPlayerHash - Retreives the Real Player Hash for Device-Commands
#			In Case of no grouping: the given hash (the normal device)
#			In Case of grouping: the hash of the groupmaster
#
#  Parameter hash = hash of device addressed
#
########################################################################################
sub SONOSPLAYER_GetRealTargetPlayerHash($) {
	my ($hash) = @_;
	
	my $udnShort = $1 if ($hash->{UDN} =~ m/(.*)_MR/);
	
	my $targetUDNShort = $udnShort;
	$targetUDNShort = $1 if (ReadingsVal($hash->{NAME}, 'ZoneGroupID', '') =~ m/(.*?):/);
	
	return SONOS_getSonosPlayerByUDN($targetUDNShort.'_MR') if ($udnShort ne $targetUDNShort);
	return $hash;
}

########################################################################################
#
#  SONOSPLAYER_Undef - Implements UndefFn function
#
#  Parameter hash = hash of device addressed
#
########################################################################################
sub SONOSPLAYER_Undef ($) {
	my ($hash) = @_;
  
	RemoveInternalTimer($hash);
  
	return undef;
}

########################################################################################
#
#  SONOSPLAYER_Log - Log to the normal Log-command with additional Infomations like Thread-ID and the prefix 'SONOSPLAYER'
#
########################################################################################
sub SONOSPLAYER_Log($$$) {
	my ($devicename, $level, $text) = @_;
	  
	Log3 $devicename, $level, 'SONOSPLAYER'.threads->tid().': '.$text;
}

1;

=pod
=begin html

<a name="SONOSPLAYER"></a>
<h3>SONOSPLAYER</h3>
<p>FHEM module to work with a Sonos Zoneplayer</p>
<p>For more informations have also a closer look at the wiki at <a href="http://www.fhemwiki.de/wiki/Sonos_Anwendungsbeispiel">http://www.fhemwiki.de/wiki/Sonos_Anwendungsbeispiel</a></p>
<h4>Example</h4>
<p>
<code>define Sonos_Wohnzimmer SONOSPLAYER RINCON_000EFEFEFEF401400</code>
</p>
<br />
<a name="SONOSPLAYERdefine"></a>
<h4>Define</h4>
<code>define &lt;name&gt; SONOSPLAYER &lt;udn&gt;</code>
<p>
<code>&lt;udn&gt;</code><br /> MAC-Address based identifier of the zoneplayer</p>
<p>
<br />
<br />
<a name="SONOSPLAYERset"></a>
<h4>Set</h4>
<ul>
<li><a name="SONOSPLAYER_setter_Play">
<code>set &lt;name&gt; Play</code></a>
<br /> Starts playing</li>
<li><a name="SONOSPLAYER_setter_Pause">
<code>set &lt;name&gt; Pause</code></a>
<br /> Pause the playing</li>
<li><a name="SONOSPLAYER_setter_Stop">
<code>set &lt;name&gt; Stop</code></a>
<br /> Stops the playing</li>
<li><a name="SONOSPLAYER_setter_Next">
<code>set &lt;name&gt; Next</code></a>
<br /> Jumps to the beginning of the next title</li>
<li><a name="SONOSPLAYER_setter_Previous">
<code>set &lt;name&gt; Previous</code></a>
<br /> Jumps to the beginning of the previous title.</li>
<li><a name="SONOSPLAYER_setter_LoadPlaylist">
<code>set &lt;name&gt; LoadPlaylist &lt;Playlistname&gt; [EmptyQueueBeforeImport]</code></a>
<br /> Loads the named playlist to the current playing queue. The parameter should be URL-encoded for proper naming of lists with special characters. The Playlistname can be a filename and then must be startet with 'file:' (e.g. 'file:c:/Test.m3u')<br />If EmptyQueueBeforeImport is given and set to 1, the queue will be emptied before the import process. If not given, the parameter will be interpreted as 1.</li>
<li><a name="SONOSPLAYER_setter_SavePlaylist">
<code>set &lt;name&gt; SavePlaylist &lt;Playlistname&gt;</code></a>
<br /> Saves the current queue as a playlist with the given name. An existing playlist with the same name will be overwritten. The parameter should be URL-encoded for proper naming of lists with special characters. The Playlistname can be a filename and then must be startet with 'file:' (e.g. 'file:c:/Test.m3u')</li>
<li><a name="SONOSPLAYER_setter_EmptyPlaylist">
<code>set &lt;name&gt; EmptyPlaylist</code></a>
<br /> Clears the current queue</li>
<li><a name="SONOSPLAYER_setter_CurrentPlaylist">
<code>set &lt;name&gt; CurrentPlaylist</code></a>
<br /> Sets the current playing to the current queue, but doesn't start playing (e.g. after hearing of a radiostream, where the current playlist still exists but is currently "not in use")</li>
<li><a name="SONOSPLAYER_setter_StartFavourite">
<code>set &lt;name&gt; StartFavourite &lt;Favouritename&gt; [NoStart]</code></a>
<br /> Starts the named sonos-favorite. The parameter should be URL-encoded for proper naming of lists with special characters. If the Word 'NoStart' is given as second parameter, than the Loading will be done, but the playing-state is leaving untouched e.g. not started.</li>
<li><a name="SONOSPLAYER_setter_LoadRadio">
<code>set &lt;name&gt; LoadRadio &lt;Radiostationname&gt;</code></a>
<br /> Loads the named radiostation (favorite). The current queue will not be touched but deactivated. The parameter should be URL-encoded for proper naming of lists with special characters.</li>
<li><a name="SONOSPLAYER_setter_Mute">
<code>set &lt;name&gt; Mute &lt;State&gt;</code></a>
<br /> Sets the mute-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_MuteT">
<code>set &lt;name&gt; MuteT</code></a>
<br /> Toggles the mute state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_Shuffle">
<code>set &lt;name&gt; Shuffle &lt;State&gt;</code></a>
<br /> Sets the shuffle-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_Repeat">
<code>set &lt;name&gt; Repeat &lt;State&gt;</code></a>
<br /> Sets the repeat-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_CrossfadeMode">
<code>set &lt;name&gt; CrossfadeMode &lt;State&gt;</code></a>
<br /> Sets the crossfade-mode. Retrieves the new mode as the result.</li>
<li><a name="SONOSPLAYER_setter_LEDState">
<code>set &lt;name&gt; LEDState &lt;State&gt;</code></a>
<br /> Sets the LED state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_VolumeD">
<code>set &lt;name&gt; VolumeD</code></a>
<br /> Turns the volume by volumeStep-ticks down.</li>
<li><a name="SONOSPLAYER_setter_VolumeU">
<code>set &lt;name&gt; VolumeU</code></a>
<br /> Turns the volume by volumeStep-ticks up.</li>
<li><a name="SONOSPLAYER_setter_Volume">
<code>set &lt;name&gt; Volume &lt;VolumeLevel&gt; [RampType]</code></a>
<br /> Sets the volume to the given value. The value could be a relative value with + or - sign. In this case the volume will be increased or decreased according to this value. Retrieves the new volume as the result.<br />Optional can be a RampType defined  with a value between 1 and 3 which describes different templates defined by the Sonos-System.</li>
<li><a name="SONOSPLAYER_setter_Bass">
<code>set &lt;name&gt; Bass &lt;BassValue&gt;</code></a>
<br /> Sets the bass to the given value. The value can range from -10 to 10. Retrieves the new bassvalue as the result.</li>
<li><a name="SONOSPLAYER_setter_Treble">
<code>set &lt;name&gt; Treble &lt;TrebleValue&gt;</code></a>
<br /> Sets the treble to the given value. The value can range from -10 to 10. Retrieves the new treblevalue as the result.</li>
<li><a name="SONOSPLAYER_setter_Balance">
<code>set &lt;name&gt; Balance &lt;BalanceValue&gt;</code></a>
<br /> Sets the balance to the given value. The value can range from -100 (full left) to 100 (full right). Retrieves the new balancevalue as the result.</li>
<li><a name="SONOSPLAYER_setter_Loudness">
<code>set &lt;name&gt; Loudness &lt;State&gt;</code></a>
<br /> Sets the loudness-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_VolumeSave">
<code>set &lt;name&gt; VolumeSave &lt;VolumeLevel&gt;</code></a>
<br /> Sets the volume to the given value. The value could be a relative value with + or - sign. In this case the volume will be increased or decreased according to this value. Retrieves the new volume as the result. Additionally it saves the old volume to a reading for restoreing.</li>
<li><a name="SONOSPLAYER_setter_VolumeRestore">
<code>set &lt;name&gt; VolumeRestore</code></a>
<br /> Restores the volume of a formerly saved volume.</li>
<li><a name="SONOSPLAYER_setter_CurrentTrackPosition">
<code>set &lt;name&gt; CurrentTrackPosition &lt;TimePosition&gt;</code></a>
<br /> Sets the current timeposition inside the title to the given value.</li>
<li><a name="SONOSPLAYER_setter_Track">
<code>set &lt;name&gt; Track &lt;TrackNumber|Random&gt;</code></a>
<br /> Sets the track with the given tracknumber as the current title. If the tracknumber is the word <code>Random</code> a random track will be selected.</li>
<li><a name="SONOSPLAYER_setter_PlayURI">
<code>set &lt;name&gt; PlayURI &lt;songURI&gt; [Volume]</code></a>
<br />Plays the given MP3-File with the optional given volume.</li>
<li><a name="SONOSPLAYER_setter_PlayURITemp">
<code>set &lt;name&gt; PlayURITemp &lt;songURI&gt; [Volume]</code></a>
<br />Plays the given MP3-File with the optional given volume as a temporary file. After playing it, the whole state is reconstructed and continues playing at the former saved position and volume and so on. If the file given is a stream (exactly: a file where the running time could not be determined), the call would be identical to <code>,PlayURI</code>, e.g. nothing is restored after playing.</li>
<li><a name="SONOSPLAYER_setter_AddURIToQueue">
<code>set &lt;name&gt; AddURIToQueue &lt;songURI&gt;</code></a>
<br />Adds the given MP3-File at the current position into the queue.</li>
<li><a name="SONOSPLAYER_setter_Speak">
<code>set &lt;name&gt; Speak &lt;Volume&gt; &lt;Language&gt; &lt;Text&gt;</code></a>
<br />Uses the Google Text-To-Speech-Engine for generating MP3-Files of the given text and plays it on the SonosPlayer. Possible languages can be obtained from Google. e.g. "de", "en", "fr", "es"...</li>
<li><a name="SONOSPLAYER_setter_Alarm">
<code>set &lt;name&gt; Alarm (Create|Update|Delete) &lt;ID&gt; &lt;Datahash&gt;</code></a>
<br />Can be used for working on alarms:<ul><li><b>Create:</b> Creates an alarm-entry with the given datahash.</li><li><b>Update:</b> Updates the alarm-entry with the given id and datahash.</li><li><b>Delete:</b> Deletes the alarm-entry with the given id.</li></ul><br /><b>The Datahash:</b><br />The Format is a perl-hash and is interpreted with the eval-function.<br />e.g.: { Repeat =&gt; 1 }<br /><br />The following entries are allowed/neccessary:<ul><li>StartTime</li><li>Duration</li><li>Recurrence_Once</li><li>Recurrence_Monday</li><li>Recurrence_Tuesday</li><li>Recurrence_Wednesday</li><li>Recurrence_Thursday</li><li>Recurrence_Friday</li><li>Recurrence_Saturday</li><li>Recurrence_Sunday</li><li>Enabled</li><li>ProgramURI</li><li>ProgramMetaData</li><li>Shuffle</li><li>Repeat</li><li>Volume</li><li>IncludeLinkedZones</li></ul><br />e.g.:<ul><li>set Sonos_Wohnzimmer Alarm Create 0 { Enabled =&gt; 1, Volume =&gt; 35, StartTime =&gt; '00:00:00', Duration =&gt; '00:15:00', Repeat =&gt; 0, Shuffle =&gt; 0, ProgramURI =&gt; 'x-rincon-buzzer:0', ProgramMetaData =&gt; '', Recurrence_Once =&gt; 0, Recurrence_Monday =&gt; 1, Recurrence_Tuesday =&gt; 1, Recurrence_Wednesday =&gt; 1, Recurrence_Thursday =&gt; 1, Recurrence_Friday =&gt; 1, Recurrence_Saturday =&gt; 0, Recurrence_Sunday =&gt; 0, IncludeLinkedZones =&gt; 0 }</li><li>set Sonos_Wohnzimmer Alarm Update 17 { Shuffle =&gt; 1 }</li><li>set Sonos_Wohnzimmer Alarm Delete 17 {}</li></ul></li>
<li><a name="SONOSPLAYER_setter_DailyIndexRefreshTime">
<code>set &lt;name&gt; DailyIndexRefreshTime &lt;time&gt;</code></a>
<br />Sets the current DailyIndexRefreshTime for the whole bunhc of Zoneplayers.</li>
<code>set &lt;name&gt; AddMember &lt;devicename&gt;</code></a>
<br />Adds the given devicename to the current device as a groupmember. The current playing of the current device goes on and will be transfered to the given device (the new member).</li>
<li><a name="SONOSPLAYER_setter_RemoveMember">
<code>set &lt;name&gt; RemoveMember &lt;devicename&gt;</code></a>
<br />Removes the given device, so that they both are not longer a group. The current playing of the current device goes on normally. The cutted device stops his playing and has no current playlist anymore (since Sonos Version 4.2 the old playlist will be restored).</li>
<li><a name="SONOSPLAYER_setter_GroupVolume">
<code>set &lt;name&gt; GroupVolume &lt;VolumeLevel&gt;</code></a>
<br />Sets the group-volume in the way the original controller does. This means, that the relative volumelevel between the different players will be saved during change.</li>
<li><a name="SONOSPLAYER_setter_GroupMute">
<code>set &lt;name&gt; GroupMute &lt;State&gt;</code></a>
<br />Sets the mute state of the complete group in one step. The value can be on or off.</li>
<li><a name="SONOSPLAYER_setter_Reboot">
<code>set &lt;name&gt; Reboot</code></a>
<br />Initiates a reboot on the Zoneplayer.</li>
<li><a name="SONOSPLAYER_setter_Wifi">
<code>set &lt;name&gt; Wifi &lt;State&gt;</code></a>
<br />Sets the WiFi-State of the given Player. Can be 'off', 'persist-off' or 'on'.</li>
</ul>
<br />
<a name="SONOSPLAYERget"></a> 
<h4>Get</h4>
<ul>
<li><a name="SONOSPLAYER_getter_CurrentTrackPosition">
<code>get &lt;name&gt; CurrentTrackPosition</code></a>
<br /> Retrieves the current timeposition inside a title</li>
<li><a name="SONOSPLAYER_getter_Favourites">
<code>get &lt;name&gt; Favourites</code></a>
<br /> Retrieves a list with the names of all sonos favourites. This getter retrieves the same list on all Zoneplayer. The format is a comma-separated list with quoted names of favourites. e.g. "Liste 1","Entry 2","Test"</li>
<li><a name="SONOSPLAYER_getter_Playlists">
<code>get &lt;name&gt; Playlists</code></a>
<br /> Retrieves a list with the names of all saved queues (aka playlists). This getter retrieves the same list on all Zoneplayer. The format is a comma-separated list with quoted names of playlists. e.g. "Liste 1","Liste 2","Test"</li>
<li><a name="SONOSPLAYER_getter_Radios">
<code>get &lt;name&gt; Radios</code></a>
<br /> Retrieves a list woth the names of all saved radiostations (favorites). This getter retrieves the same list on all Zoneplayer. The format is a comma-separated list with quoted names of radiostations. e.g. "Sender 1","Sender 2","Test"</li>
<li><a name="SONOSPLAYER_getter_EthernetPortStatus">
<code>get &lt;name&gt; EthernetPortStatus &lt;PortNumber&gt;</code></a>
<br /> Gets the Ethernet-Portstatus of the given Port. Can be 'Active' or 'Inactive'.</li>
</ul>
<br />
<a name="SONOSPLAYERattr"></a>
<h4>Attributes</h4>
<ul>
<li><a name="SONOSPLAYER_attribut_disable"><code>attr &lt;name&gt; disable &lt;int&gt;</code>
</a><br /> One of (0,1). Disables the event-worker for this Sonosplayer.</li>
<li><a name="SONOSPLAYER_attribut_volumeStep"><code>attr &lt;name&gt; volumeStep &lt;int&gt;</code>
</a><br /> One of (0..100). Defines the stepwidth for subsequent calls of <code>VolumeU</code> and <code>VolumeD</code>.</li>
<li><a name="SONOSPLAYER_attribut_generateVolumeSlider"><code>attr &lt;name&gt; generateVolumeSlider &lt;int&gt;</code>
</a><br /> One of (0,1). Enables a slider for volumecontrol in detail view.</li>
<li><a name="SONOSPLAYER_attribut_generateVolumeEvent"><code>attr &lt;name&gt; generateVolumeEvent &lt;int&gt;</code>
</a><br /> One of (0,1). Enables an event generated at volumechanges if minVolume or maxVolume is set.</li>
<li><a name="SONOSPLAYER_attribut_generateSomethingChangedEvent"><code>attr &lt;name&gt; generateSomethingChangedEvent &lt;int&gt;</code>
</a><br /> One of (0,1). 1 if a 'SomethingChanged'-Event should be generated. This event is thrown every time an event is generated. This is useful if you wants to be notified on every change with a single event.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize1"><code>attr &lt;name&gt; generateInfoSummarize1 &lt;string&gt;</code>
</a><br /> Generates the reading 'InfoSummarize1' with the given format. More Information on this in the examples-section.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize2"><code>attr &lt;name&gt; generateInfoSummarize2 &lt;string&gt;</code>
</a><br /> Generates the reading 'InfoSummarize2' with the given format. More Information on this in the examples-section.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize3"><code>attr &lt;name&gt; generateInfoSummarize3 &lt;string&gt;</code>
</a><br /> Generates the reading 'InfoSummarize3' with the given format. More Information on this in the examples-section.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize4"><code>attr &lt;name&gt; generateInfoSummarize4 &lt;string&gt;</code>
</a><br /> Generates the reading 'InfoSummarize4' with the given format. More Information on this in the examples-section.</li>
<li><a name="SONOSPLAYER_attribut_stateVariable"><code>attr &lt;name&gt; stateVariable &lt;string&gt;</code>
</a><br /> One of (TransportState,NumberOfTracks,Track,TrackURI,TrackDuration,Title,Artist,Album,OriginalTrackNumber,AlbumArtist,Sender,SenderCurrent,SenderInfo,StreamAudio,NormalAudio,AlbumArtURI,nextTrackDuration,nextTrackURI,nextAlbumArtURI,nextTitle,nextArtist,nextAlbum,nextAlbumArtist,nextOriginalTrackNumber,Volume,Mute,Shuffle,Repeat,CrossfadeMode,Balance,HeadphoneConnected,SleepTimer,Presence,RoomName,SaveRoomName,PlayerType,Location,SoftwareRevision,SerialNum,InfoSummarize1,InfoSummarize2,InfoSummarize3,InfoSummarize4). Defines, which variable has to be copied to the content of the state-variable.</li>
<li><a name="SONOSPLAYER_attribut_minVolume"><code>attr &lt;name&gt; minVolume &lt;int&gt;</code>
</a><br /> One of (0..100). Define a minimal volume for this Zoneplayer</li>
<li><a name="SONOSPLAYER_attribut_maxVolume"><code>attr &lt;name&gt; maxVolume &lt;int&gt;</code>
</a><br /> One of (0..100). Define a maximal volume for this Zoneplayer</li>
<li><a name="SONOSPLAYER_attribut_minVolumeHeadphone"><code>attr &lt;name&gt; minVolumeHeadphone &lt;int&gt;</code>
</a><br /> One of (0..100). Define a minimal volume for this Zoneplayer for use with headphones</li>
<li><a name="SONOSPLAYER_attribut_maxVolumeHeadphone"><code>attr &lt;name&gt; maxVolumeHeadphone &lt;int&gt;</code>
</a><br /> One of (0..100). Define a maximal volume for this Zoneplayer for use with headphones</li>
<li><a name="SONOSPLAYER_attribut_getAlarms"><code>attr &lt;name&gt; getAlarms &lt;int&gt;</code>
</a><br /> One of (0..1). Initializes a callback-method for Alarms. This included the information of the DailyIndexRefreshTime.</li>
<li><a name="SONOSPLAYER_attribut_buttonEvents"><code>attr &lt;name&gt; buttonEvents &lt;Time:Pattern&gt;[ &lt;Time:Pattern&gt; ...]</code>
</a><br /> Defines that after pressing a specified sequence of buttons at the player an event has to be thrown. The definition itself is a tupel: the first part (before the colon) is the time in seconds, the second part (after the colon) is the button sequence of this event.<br />
The following button-shortcuts are possible: <ul><li><b>M</b>: The Mute-Button</li><li><b>H</b>: The Headphone-Connector</li><li><b>U</b>: Up-Button (Volume Up)</li><li<><b>D</b>: Down-Button (Volume Down)</li></ul><br />
The event thrown is named <code>ButtonEvent</code>, the value is the defined button-sequence.<br />
E.G.: <code>2:MM</code><br />
Here an event is defined, where in time of 2 seconds the Mute-Button has to be pressed 2 times. The created event is named <code>ButtonEvent</code> and has the value <code>MM</code>.</li>
</ul>
<br />
<a name="SONOSPLAYERexamples"></a>
<h4>Examples / Tips</h4>
<ul>
<li><a name="SONOSPLAYER_examples_InfoSummarize">Format of InfoSummarize:</a><br />
<code>infoSummarizeX := &lt;NormalAudio&gt;:summarizeElem:&lt;/NormalAudio&gt; &lt;StreamAudio&gt;:summarizeElem:&lt;/StreamAudio&gt;</code>|:summarizeElem:<br />
<code>:summarizeElem: := &lt;:variable:[ prefix=":text:"][ suffix=":text:"][ ifempty=":text:"]/&gt;</code><br />
<code>:variable: := TransportState|NumberOfTracks|Track|TrackURI|TrackDuration|Title|Artist|Album|OriginalTrackNumber|AlbumArtist|Sender|SenderCurrent|SenderInfo|StreamAudio|NormalAudio|AlbumArtURI|nextTrackDuration|nextTrackURI|nextAlbumArtURI|nextTitle|nextArtist|nextAlbum|nextAlbumArtist|nextOriginalTrackNumber|Volume|Mute|Shuffle|Repeat|CrossfadeMode|Balance|HeadphoneConnected|SleepTimer|Presence|RoomName|SaveRoomName|PlayerType|Location|SoftwareRevision|SerialNum|InfoSummarize1|InfoSummarize2|InfoSummarize3|InfoSummarize4</code><br />
<code>:text: := [Any text without double-quotes]</code><br />
</ul>

=end html

=begin html_de

<a name="SONOSPLAYER"></a>
<h3>SONOSPLAYER</h3>
<p>FHEM Modul für die Steuerung eines Sonos Zoneplayer</p>
<p>Für weitere Hinweise und Beschreibungen bitte auch im Wiki unter <a href="http://www.fhemwiki.de/wiki/Sonos_Anwendungsbeispiel">http://www.fhemwiki.de/wiki/Sonos_Anwendungsbeispiel</a> nachschauen.</p>
<h4>Example</h4>
<p>
<code>define Sonos_Wohnzimmer SONOSPLAYER RINCON_000EFEFEFEF401400_MR</code>
</p>
<br />
<a name="SONOSPLAYERdefine"></a>
<h4>Definition</h4>
<code>define &lt;name&gt; SONOSPLAYER &lt;udn&gt;</code>
<p>
<code>&lt;udn&gt;</code><br /> MAC-Addressbasierter eindeutiger Bezeichner des Zoneplayer</p>
<p>
<br />
<br />
<a name="SONOSPLAYERset"></a>
<h4>Set</h4>
<ul>
<li><a name="SONOSPLAYER_setter_Play">
<code>set &lt;name&gt; Play</code></a>
<br /> Startet die Wiedergabe</li>
<li><a name="SONOSPLAYER_setter_Pause">
<code>set &lt;name&gt; Pause</code></a>
<br /> Pausiert die Wiedergabe</li>
<li><a name="SONOSPLAYER_setter_Stop">
<code>set &lt;name&gt; Stop</code></a>
<br /> Stoppt die Wiedergabe</li>
<li><a name="SONOSPLAYER_setter_Next">
<code>set &lt;name&gt; Next</code></a>
<br /> Springt an den Anfang des nächsten Titels</li>
<li><a name="SONOSPLAYER_setter_Previous">
<code>set &lt;name&gt; Previous</code></a>
<br /> Springt an den Anfang des vorherigen Titels.</li>
<li><a name="SONOSPLAYER_setter_LoadPlaylist">
<code>set &lt;name&gt; LoadPlaylist &lt;Playlistname&gt; [EmptyQueueBeforeImport]</code></a>
<br /> Lädt die angegebene Playlist in die aktuelle Abspielliste. Der Parameter sollte/kann URL-Encoded werden um auch Spezialzeichen zu ermöglichen. Der Playlistname kann auch ein Dateiname sein. Dann muss dieser mit 'file:' beginnen (z.B. 'file:c:/Test.m3u).<br />Wenn der Parameter EmptyQueueBeforeImport mit ''1'' angegeben wirde, wird die aktuelle Abspielliste vor dem Import geleert. Standardmäßig wird hier ''1'' angenommen.</li>
<li><a name="SONOSPLAYER_setter_SavePlaylist">
<code>set &lt;name&gt; SavePlaylist &lt;Playlistname&gt;</code></a>
<br /> Speichert die aktuelle Abspielliste unter dem angegebenen Namen. Eine bestehende Playlist mit diesem Namen wird überschrieben. Der Parameter sollte/kann URL-Encoded werden um auch Spezialzeichen zu ermöglichen. Der Playlistname kann auch ein Dateiname sein. Dann muss dieser mit 'file:' beginnen (z.B. 'file:c:/Test.m3u).</li>
<li><a name="SONOSPLAYER_setter_EmptyPlaylist">
<code>set &lt;name&gt; EmptyPlaylist</code></a>
<br /> Leert die aktuelle Abspielliste</li>
<li><a name="SONOSPLAYER_setter_CurrentPlaylist">
<code>set &lt;name&gt; CurrentPlaylist</code></a>
<br /> Setzt den Abspielmodus auf die aktuelle Abspielliste, startet aber keine Wiedergabe (z.B. nach dem Hören eines Radiostreams, wo die aktuelle Abspielliste noch existiert, aber gerade "nicht verwendet" wird)</li>
<li><a name="SONOSPLAYER_setter_StartFavourite">
<code>set &lt;name&gt; StartFavourite &lt;FavouriteName&gt; [NoStart]</code></a>
<br /> Startet den angegebenen Favoriten. Der Name bezeichnet einen Eintrag in der Sonos-Favoritenliste. Der Parameter sollte/kann URL-Encoded werden um auch Spezialzeichen zu ermöglichen. Wenn das Wort 'NoStart' als zweiter Parameter angegeben wurde, dann wird der Favorit geladen und fertig vorbereitet, aber nicht explizit gestartet.</li>
<li><a name="SONOSPLAYER_setter_LoadRadio">
<code>set &lt;name&gt; LoadRadio &lt;Radiostationname&gt;</code></a>
<br /> Startet den angegebenen Radiostream. Der Name bezeichnet einen Sender in der Radiofavoritenliste. Die aktuelle Abspielliste wird nicht verändert. Der Parameter sollte/kann URL-Encoded werden um auch Spezialzeichen zu ermöglichen.</li>
<li><a name="SONOSPLAYER_setter_Mute">
<code>set &lt;name&gt; Mute &lt;State&gt;</code></a>
<br /> Setzt den angegebenen Mute-Zustand. Liefert den aktuell gültigen Mute-Zustand.</li>
<li><a name="SONOSPLAYER_setter_MuteT">
<code>set &lt;name&gt; MuteT</code></a>
<br /> Schaltet den Zustand des Mute-Zustands um. Liefert den aktuell gültigen Mute-Zustand.</li>
<li><a name="SONOSPLAYER_setter_Shuffle">
<code>set &lt;name&gt; Shuffle &lt;State&gt;</code></a>
<br /> Legt den Zustand des Shuffle-Zustands fest. Liefert den aktuell gültigen Shuffle-Zustand.</li>
<li><a name="SONOSPLAYER_setter_Repeat">
<code>set &lt;name&gt; Repeat &lt;State&gt;</code></a>
<br /> Legt den Zustand des Repeat-Zustands fest. Liefert den aktuell gültigen Repeat-Zustand.</li>
<li><a name="SONOSPLAYER_setter_CrossfadeMode">
<code>set &lt;name&gt; CrossfadeMode &lt;State&gt;</code></a>
<br /> Legt den Zustand des Crossfade-Mode fest. Liefert den aktuell gültigen Crossfade-Mode.</li>
<li><a name="SONOSPLAYER_setter_LEDState">
<code>set &lt;name&gt; LEDState &lt;State&gt;</code></a>
<br /> Legt den Zustand der LED fest. Liefert den aktuell gültigen Zustand.</li>
<li><a name="SONOSPLAYER_setter_VolumeD">
<code>set &lt;name&gt; VolumeD</code></a>
<br /> Verringert die aktuelle Lautstärke um volumeStep-Einheiten.</li>
<li><a name="SONOSPLAYER_setter_VolumeU">
<code>set &lt;name&gt; VolumeU</code></a>
<br /> Erhöht die aktuelle Lautstärke um volumeStep-Einheiten.</li>
<li><a name="SONOSPLAYER_setter_Volume">
<code>set &lt;name&gt; Volume &lt;VolumeLevel&gt; [RampType]</code></a>
<br /> Setzt die aktuelle Lautstärke auf den angegebenen Wert. Der Wert kann ein relativer Wert mittels + oder - Zeichen sein. Liefert den aktuell gültigen Lautstärkewert zurück.<br />Optional kann ein RampType übergeben werden, der einen Wert zwischen 1 und 3 annehmen kann, und verschiedene von Sonos festgelegte Muster beschreibt.</li>
<li><a name="SONOSPLAYER_setter_Bass">
<code>set &lt;name&gt; Bass &lt;BassValue&gt;</code></a>
<br /> Setzt den Basslevel auf den angegebenen Wert. Der Wert kann zwischen -10 bis 10 sein. Gibt den wirklich eingestellten Basslevel als Ergebnis zurück.</li>
<li><a name="SONOSPLAYER_setter_Treble">
<code>set &lt;name&gt; Treble &lt;TrebleValue&gt;</code></a>
<br /> Setzt den Treblelevel auf den angegebenen Wert. Der Wert kann zwischen -10 bis 10 sein. Gibt den wirklich eingestellten Treblelevel als Ergebnis zurück.</li>
<li><a name="SONOSPLAYER_setter_Balance">
<code>set &lt;name&gt; Balance &lt;BalanceValue&gt;</code></a>
<br /> Setzt die Balance auf den angegebenen Wert. Der Wert kann zwischen -100 (voll links) bis 100 (voll rechts) sein. Gibt die wirklich eingestellte Balance als Ergebnis zurück.</li>
<li><a name="SONOSPLAYER_setter_Loudness">
<code>set &lt;name&gt; Loudness &lt;State&gt;</code></a>
<br /> Setzt den angegebenen Loudness-Zustand. Liefert den aktuell gültigen Loudness-Zustand.</li>
<li><a name="SONOSPLAYER_setter_VolumeSave">
<code>set &lt;name&gt; VolumeSave &lt;VolumeLevel&gt;</code></a>
<br /> Setzt die aktuelle Lautstärke auf den angegebenen Wert. Der Wert kann ein relativer Wert mittels + oder - Zeichen sein. Liefert den aktuell gültigen Lautstärkewert zurück. Zusätzlich wird der alte Lautstärkewert gespeichert und kann mittels <code>VolumeRestore</code> wiederhergestellt werden.</li>
<li><a name="SONOSPLAYER_setter_VolumeRestore">
<code>set &lt;name&gt; VolumeRestore</code></a>
<br /> Stellt die mittels <code>VolumeSave</code> gespeicherte Lautstärke wieder her.</li>
<li><a name="SONOSPLAYER_setter_CurrentTrackPosition">
<code>set &lt;name&gt; CurrentTrackPosition &lt;TimePosition&gt;</code></a>
<br /> Setzt die Abspielposition innerhalb des Liedes auf den angegebenen Zeitwert (z.B. 0:01:15).</li>
<li><a name="SONOSPLAYER_setter_Track">
<code>set &lt;name&gt; Track &lt;TrackNumber|Random&gt;</code></a>
<br /> Aktiviert den angebenen Titel der aktuellen Abspielliste. Wenn als Tracknummer der Wert <code>Random</code> angegeben wird, dann wird eine zufällige Trackposition ausgewählt.</li>
<li><a name="SONOSPLAYER_setter_PlayURI">
<code>set &lt;name&gt; PlayURI &lt;songURI&gt; [Volume]</code></a>
<br /> Spielt die angegebene MP3-Datei ab. Dabei kann eine Lautstärke optional mit angegeben werden.</li>
<li><a name="SONOSPLAYER_setter_PlayURITemp">
<code>set &lt;name&gt; PlayURITemp &lt;songURI&gt; [Volume]</code></a>
<br /> Spielt die angegebene MP3-Datei mit der optionalen Lautstärke als temporäre Wiedergabe ab. Nach dem Abspielen wird der vorhergehende Zustand wiederhergestellt, und läuft an der unterbrochenen Stelle weiter. Wenn die Länge der Datei nicht ermittelt werden kann (z.B. bei Streams), läuft die Wiedergabe genauso wie bei <code>PlayURI</code> ab, es wird also nichts am Ende (wenn es eines geben sollte) wiederhergestellt.</li>
<li><a name="SONOSPLAYER_setter_AddURIToQueue">
<code>set &lt;name&gt; AddURIToQueue &lt;songURI&gt;</code></a>
<br /> Fügt die angegebene MP3-Datei an der aktuellen Stelle in die Abspielliste ein.</li>
<li><a name="SONOSPLAYER_setter_Speak">
<code>set &lt;name&gt; Speak &lt;Volume&gt; &lt;Language&gt; &lt;Text&gt;</code></a>
<br /> Verwendet die Google Text-To-Speech-Engine um den angegebenen Text in eine MP3-Datei umzuwandeln und anschließend mittels <code>PlayURITemp</code> als Durchsage abzuspielen. Mögliche Sprachen können auf der Google-Seite nachgesehen werden. Möglich sind z.B. "de", "en", "fr", "es"...</li>
<li><a name="SONOSPLAYER_setter_Alarm">
<code>set &lt;name&gt; Alarm (Create|Update|Delete) &lt;ID&gt; &lt;Datahash&gt;</code></a>
<br />Diese Anweisung wird für die Bearbeitung der Alarme verwendet:<ul><li><b>Create:</b> Erzeugt einen neuen Alarm-Eintrag mit den übergebenen Hash-Daten.</li><li><b>Update:</b> Aktualisiert den Alarm mit der übergebenen ID und den angegebenen Hash-Daten.</li><li><b>Delete:</b> Löscht den Alarm-Eintrag mit der übergebenen ID.</li></ul><br /><b>Die Hash-Daten:</b><br />Das Format ist ein Perl-Hash und wird mittels der eval-Funktion interpretiert.<br />e.g.: { Repeat =&gt; 1 }<br /><br />Die folgenden Schlüssel sind zulässig/notwendig:<ul><li>StartTime</li><li>Duration</li><li>Recurrence_Once</li><li>Recurrence_Monday</li><li>Recurrence_Tuesday</li><li>Recurrence_Wednesday</li><li>Recurrence_Thursday</li><li>Recurrence_Friday</li><li>Recurrence_Saturday</li><li>Recurrence_Sunday</li><li>Enabled</li><li>ProgramURI</li><li>ProgramMetaData</li><li>Shuffle</li><li>Repeat</li><li>Volume</li><li>IncludeLinkedZones</li></ul><br />z.B.:<ul><li>set Sonos_Wohnzimmer Alarm Create 0 { Enabled =&gt; 1, Volume =&gt; 35, StartTime =&gt; '00:00:00', Duration =&gt; '00:15:00', Repeat =&gt; 0, Shuffle =&gt; 0, ProgramURI =&gt; 'x-rincon-buzzer:0', ProgramMetaData =&gt; '', Recurrence_Once =&gt; 0, Recurrence_Monday =&gt; 1, Recurrence_Tuesday =&gt; 1, Recurrence_Wednesday =&gt; 1, Recurrence_Thursday =&gt; 1, Recurrence_Friday =&gt; 1, Recurrence_Saturday =&gt; 0, Recurrence_Sunday =&gt; 0, IncludeLinkedZones =&gt; 0 }</li><li>set Sonos_Wohnzimmer Alarm Update 17 { Shuffle =&gt; 1 }</li><li>set Sonos_Wohnzimmer Alarm Delete 17 {}</li></ul></li>
<li><a name="SONOSPLAYER_setter_DailyIndexRefreshTime">
<code>set &lt;name&gt; DailyIndexRefreshTime &lt;time&gt;</code></a>
<br />Setzt die aktuell gültige DailyIndexRefreshTime für alle Zoneplayer.</li>
<li><a name="SONOSPLAYER_setter_AddMember">
<code>set &lt;name&gt; AddMember &lt;devicename&gt;</code></a>
<br />Fügt dem Device das übergebene Device als Gruppenmitglied hinzu. Die Wiedergabe des aktuellen Devices bleibt erhalten, und wird auf das angegebene Device mit übertragen.</li>
<li><a name="SONOSPLAYER_setter_RemoveMember">
<code>set &lt;name&gt; RemoveMember &lt;devicename&gt;</code></a>
<br />Entfernt dem Device das übergebene Device, sodass die beiden keine Gruppe mehr bilden. Die Wiedergabe des aktuellen Devices läuft normal weiter. Das abgetrennte Device stoppt seine Wiedergabe, und hat keine aktuelle Abspielliste mehr (seit Sonos Version 4.2 hat der Player wieder die Playliste von vorher aktiv).</li>
<li><a name="SONOSPLAYER_setter_GroupVolume">
<code>set &lt;name&gt; GroupVolume &lt;VolumeLevel&gt;</code></a>
<br />Setzt die Gruppenlautstärke in der Art des Original-Controllers. Das bedeutet, dass das Lautstärkeverhältnis der Player zueinander beim Anpassen erhalten bleibt.</li>
<li><a name="SONOSPLAYER_setter_GroupMute">
<code>set &lt;name&gt; GroupMute &lt;State&gt;</code></a>
<br />Setzt den Mute-Zustand für die komplette Gruppe in einem Schritt. Der Wert kann on oder off sein.</li>
<li><a name="SONOSPLAYER_setter_Reboot">
<code>set &lt;name&gt; Reboot</code></a>
<br />Führt für den Zoneplayer einen Neustart durch.</li>
<li><a name="SONOSPLAYER_setter_Wifi">
<code>set &lt;name&gt; Wifi &lt;State&gt;</code></a>
<br />Setzt den WiFi-Zustand des Players. Kann 'off', 'persist-off' oder 'on' sein.</li>
</ul>
<br />
<a name="SONOSPLAYERget"></a> 
<h4>Get</h4>
<ul>
<li><a name="SONOSPLAYER_getter_CurrentTrackPosition">
<code>get &lt;name&gt; CurrentTrackPosition</code></a>
<br /> Liefert die aktuelle Position innerhalb des Titels.</li>
<li><a name="SONOSPLAYER_getter_Favourites">
<code>get &lt;name&gt; Favourites</code></a>
<br /> Liefert eine Liste mit den Namen aller gespeicherten Sonos-Favoriten. Das Format der Liste ist eine Komma-Separierte Liste, bei der die Namen in doppelten Anführungsstrichen stehen. z.B. "Liste 1","Eintrag 2","Test"</li>
<li><a name="SONOSPLAYER_getter_Playlists">
<code>get &lt;name&gt; Playlists</code></a>
<br /> Liefert eine Liste mit den Namen aller gespeicherten Playlists. Das Format der Liste ist eine Komma-Separierte Liste, bei der die Namen in doppelten Anführungsstrichen stehen. z.B. "Liste 1","Liste 2","Test"</li>
<li><a name="SONOSPLAYER_getter_Radios">
<code>get &lt;name&gt; Radios</code></a>
<br /> Liefert eine Liste mit den Namen aller gespeicherten Radiostationen (Favoriten). Das Format der Liste ist eine Komma-Separierte Liste, bei der die Namen in doppelten Anführungsstrichen stehen. z.B. "Sender 1","Sender 2","Test"</li>
<li><a name="SONOSPLAYER_getter_EthernetPortStatus">
<code>get &lt;name&gt; EthernetPortStatus &lt;PortNumber&gt;</code></a>
<br /> Liefert den Ethernet-Portstatus des gegebenen Ports. Kann 'Active' oder 'Inactive' liefern.</li>
</ul>
<br />
<a name="SONOSPLAYERattr"></a>
<h4>Attribute</h4>
<ul>
<li><a name="SONOSPLAYER_attribut_disable"><code>attr &lt;name&gt; disable &lt;int&gt;</code>
</a><br /> One of (0,1). Deaktiviert die Event-Verarbeitung für diesen Zoneplayer.</li>
<li><a name="SONOSPLAYER_attribut_volumeStep"><code>attr &lt;name&gt; volumeStep &lt;int&gt;</code>
</a><br /> One of (0..100). Definiert die Schrittweite für die Aufrufe von <code>VolumeU</code> und <code>VolumeD</code>.</li>
<li><a name="SONOSPLAYER_attribut_generateVolumeSlider"><code>attr &lt;name&gt; generateVolumeSlider &lt;int&gt;</code>
</a><br /> One of (0,1). Aktiviert einen Slider für die Lautstärkekontrolle in der Detailansicht.</li>
<li><a name="SONOSPLAYER_attribut_generateVolumeEvent"><code>attr &lt;name&gt; generateVolumeEvent &lt;int&gt;</code>
</a><br /> One of (0,1). Aktiviert die Generierung eines Events bei Lautstärkeänderungen, wenn minVolume oder maxVolume definiert sind.</li>
<li><a name="SONOSPLAYER_attribut_generateSomethingChangedEvent"><code>attr &lt;name&gt; generateSomethingChangedEvent &lt;int&gt;</code>
</a><br /> One of (0,1). 1 wenn ein 'SomethingChanged'-Event erzeugt werden soll. Dieses Event wird immer dann erzeugt, wenn sich irgendein Wert ändert. Dies ist nützlich, wenn man immer informiert werden möchte, egal, was sich geändert hat.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize1"><code>attr &lt;name&gt; generateInfoSummarize1 &lt;string&gt;</code>
</a><br /> Erzeugt das Reading 'InfoSummarize1' mit dem angegebenen Format. Mehr Informationen dazu im Bereich Beispiele.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize2"><code>attr &lt;name&gt; generateInfoSummarize2 &lt;string&gt;</code>
</a><br /> Erzeugt das Reading 'InfoSummarize2' mit dem angegebenen Format. Mehr Informationen dazu im Bereich Beispiele.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize3"><code>attr &lt;name&gt; generateInfoSummarize3 &lt;string&gt;</code>
</a><br /> Erzeugt das Reading 'InfoSummarize3' mit dem angegebenen Format. Mehr Informationen dazu im Bereich Beispiele.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize4"><code>attr &lt;name&gt; generateInfoSummarize4 &lt;string&gt;</code>
</a><br /> Erzeugt das Reading 'InfoSummarize4' mit dem angegebenen Format. Mehr Informationen dazu im Bereich Beispiele.</li>
<li><a name="SONOSPLAYER_attribut_stateVariable"><code>attr &lt;name&gt; stateVariable &lt;string&gt;</code>
</a><br /> One of (TransportState,NumberOfTracks,Track,TrackURI,TrackDuration,Title,Artist,Album,OriginalTrackNumber,AlbumArtist,Sender,SenderCurrent,SenderInfo,StreamAudio,NormalAudio,AlbumArtURI,nextTrackDuration,nextTrackURI,nextAlbumArtURI,nextTitle,nextArtist,nextAlbum,nextAlbumArtist,nextOriginalTrackNumber,Volume,Mute,Shuffle,Repeat,CrossfadeMode,Balance,HeadphoneConnected,SleepTimer,Presence,RoomName,SaveRoomName,PlayerType,Location,SoftwareRevision,SerialNum,InfoSummarize1,InfoSummarize2,InfoSummarize3,InfoSummarize4). Gibt an, welche Variable in das Reading <code>state</code> kopiert werden soll.</li>
<li><a name="SONOSPLAYER_attribut_minVolume"><code>attr &lt;name&gt; minVolume &lt;int&gt;</code>
</a><br /> One of (0..100). Definiert die minimale Lautstärke dieses Zoneplayer.</li>
<li><a name="SONOSPLAYER_attribut_maxVolume"><code>attr &lt;name&gt; maxVolume &lt;int&gt;</code>
</a><br /> One of (0..100). Definiert die maximale Lautstärke dieses Zoneplayer.</li>
<li><a name="SONOSPLAYER_attribut_minVolumeHeadphone"><code>attr &lt;name&gt; minVolumeHeadphone &lt;int&gt;</code>
</a><br /> One of (0..100). Definiert die minimale Lautstärke dieses Zoneplayer im Kopfhörerbetrieb.</li>
<li><a name="SONOSPLAYER_attribut_maxVolumeHeadphone"><code>attr &lt;name&gt; maxVolumeHeadphone &lt;int&gt;</code>
</a><br /> One of (0..100). Definiert die maximale Lautstärke dieses Zoneplayer im Kopfhörerbetrieb.</li>
<li><a name="SONOSPLAYER_attribut_getAlarms"><code>attr &lt;name&gt; getAlarms &lt;int&gt;</code>
</a><br /> One of (0..1). Richtet eine Callback-Methode für Alarme ein. Damit wird auch die DailyIndexRefreshTime automatisch aktualisiert.</li>
<li><a name="SONOSPLAYER_attribut_buttonEvents"><code>attr &lt;name&gt; buttonEvents &lt;Time:Pattern&gt;[ &lt;Time:Pattern&gt; ...]</code>
</a><br /> Definiert, dass bei einer bestimten Tastenfolge am Player ein Event erzeugt werden soll. Die Definition der Events erfolgt als Tupel: Der erste Teil vor dem Doppelpunkt ist die Zeit in Sekunden, die berücksichtigt werden soll, der zweite Teil hinter dem Doppelpunkt definiert die Abfolge der Buttons, die für dieses Event notwendig sind.<br />
Folgende Button-Kürzel sind zulässig: <ul><li><b>M</b>: Der Mute-Button</li><li><b>H</b>: Die Headphone-Buchse</li><li><b>U</b>: Up-Button (Lautstärke Hoch)</li><li<><b>D</b>: Down-Button (Lautstärke Runter)</li></ul><br />
Das Event, das geworfen wird, heißt <code>ButtonEvent</code>, der Wert ist die definierte Tastenfolge<br />
Z.B.: <code>2:MM</code><br />
Hier wird definiert, dass ein Event erzeugt werden soll, wenn innerhalb von 2 Sekunden zweimal die Mute-Taste gedrückt wurde. Das damit erzeugte Event hat dann den Namen <code>ButtonEvent</code>, und den Wert <code>MM</code>.</li>
</ul>
<br />
<a name="SONOSPLAYERexamples"></a>
<h4>Beispiele / Hinweise</h4>
<ul>
<li><a name="SONOSPLAYER_examples_InfoSummarize">Format von InfoSummarize:</a><br />
<code>infoSummarizeX := &lt;NormalAudio&gt;:summarizeElem:&lt;/NormalAudio&gt; &lt;StreamAudio&gt;:summarizeElem:&lt;/StreamAudio&gt;</code>|:summarizeElem:<br />
<code>:summarizeElem: := &lt;:variable:[ prefix=":text:"][ suffix=":text:"][ ifempty=":text:"]/&gt;</code><br />
<code>:variable: := TransportState|NumberOfTracks|Track|TrackURI|TrackDuration|Title|Artist|Album|OriginalTrackNumber|AlbumArtist|Sender|SenderCurrent|SenderInfo|StreamAudio|NormalAudio|AlbumArtURI|nextTrackDuration|nextTrackURI|nextAlbumArtURI|nextTitle|nextArtist|nextAlbum|nextAlbumArtist|nextOriginalTrackNumber|Volume|Mute|Shuffle|Repeat|CrossfadeMode|Balance|HeadphoneConnected|SleepTimer|Presence|RoomName|SaveRoomName|PlayerType|Location|SoftwareRevision|SerialNum|InfoSummarize1|InfoSummarize2|InfoSummarize3|InfoSummarize4</code><br />
<code>:text: := [Jeder beliebige Text ohne doppelte Anführungszeichen]</code><br />
</ul>

=end html_de
=cut