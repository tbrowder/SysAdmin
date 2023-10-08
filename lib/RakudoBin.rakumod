unit module  RakudoBin;

=begin comment
# github fingerprints of the release crew
Justin DeVuyst
PGP Fingerprint: 59E6 3473 6AFD CF9C 6DBA C382 602D 51EA CA88 7C01
Patrick Böker
PGP Fingerprint: DB2B A39D 1ED9 67B5 84D6 5D71 C09F F113 BB64 10D0
Alexander Kiryuhin
PGP Fingerprint: FE75 0D15 2426 F3E5 0953 176A DE8F 8F5E 97A8 FCDE
Rakudo GitHub automation
PGP Fingerprint: 3E7E 3C6E AF91 6676 AC54 9285 A291 9382 E961 E2EE

# set of just the keys
#9825 1a7a 6987 4dd7 0120 8671 09fd ca31  key.md5
#f482 cbee 44a4 25fb 4e93 1cd1 a7a3 a054 d060 5299  key.sha1sum
=end comment

our %keys = set %(
'59E6 3473 6AFD CF9C 6DBA C382 602D 51EA CA88 7C01',
'DB2B A39D 1ED9 67B5 84D6 5D71 C09F F113 BB64 10D0',
'FE75 0D15 2426 F3E5 0953 176A DE8F 8F5E 97A8 FCDE',
'3E7E 3C6E AF91 6676 AC54 9285 A291 9382 E961 E2EE',
);

# Debian releases
our %debian-vnames is export = %(
    etch => 4,
    lenny => 5,
    squeeze => 6,
    wheezy => 7,
    jessie => 8,
    stretch => 9,
    buster => 10,
    bullsye => 11,
    bookworm => 12,
    trixie => 13,
    forky => 14,
);
our %debian-vnum is export = %debian-vnames.invert;

# Ubuntu releases
our %ubuntu-vnames is export = %(
   trusty => 14,
   xenial => 16,
   bionic => 18,
   focal => 20,
   jammy => 22,
   lunar => 23,
);
our %ubuntu-vnum is export = %ubuntu-vnames.invert;

=begin comment
# sytems confirmed
# name ; version
ubuntu; 22.04.3.LTS.Jammy.Jellyfish
ubuntu; 20.04.6.LTS.Focal.Fossa 
macos;  12.6.7
macos;  13.5  
macos;  11.7.8
mswin32; 10.0.17763.52
=end comment

=begin comment
from docs: var $*DISTRO
from docs: role Version does Systemic

basically, two methods usable:
  .name
  .version
    .Str
    .parts (a list of dot.separated items: integers, then strings)

=end comment

class OS is export {
    # the two parts of the $*DISTRO object:
    has $.name;              # debian, ubuntu, macos, mswin32, ...
    # the full Version string:
    has $.version;           # 1.0.1.buster, bookworm, ...

    # DERIVED PARTS
    # the serial part
    has $.version-serial = "";    # 10, 11, 20.4, ...
    # the string part
    has $.version-name   = "";      # buster, bookworm, xenial, ...
    # a numerical part for comparison between Ubuntu versions (x.y.z ==> x.y)
    # also used for debian version comparisons
    has $.vshort-name    = "";
    has $.vnum           = 0;

    # a hash to contain the parts
    # %h = %(
    #     version-serial => value,
    #     version-name   => value,
    #     vshort-name    => value,
    #     vnum           => value,
    # )

    submethod TWEAK {
        # TWO METHODS TO INITIATE
        unless $!name.defined and $!version.defined {
            # the two parts of the $*DISTRO object:
            $!name    = $*DISTRO.name.lc;
            $!version = $*DISTRO.version;
        }

        # what names does this module support?
        unless $!name ~~ /:i debian | ubuntu/ {
            note "WARNING: OS $!name is not supported. Please file an issue.";
        }
  
        # other pieces needed for installation by rakudo-pkg
        my %h = os-version-parts($!version.Str); # $n.Num;    # 10, 11, 20.4, ...
        $!version-serial = %h<version-serial>; 
        $!version-name   = %h<version-name>; 
        # we have to support multiple integer chunks for numerical comparison
        $!vshort-name    = %h<vshort-name>; 
        $!vnum           = %h<vnum>; 
    }

    sub os-version-parts(Str $version --> Hash) is export { 
        # break version.parts into serial and string parts
        # create a numerical part for serial comparison
        my @parts = $version.split('.');
        my $s = ""; # string part
        my $n = ""; # serial part
        my @c;      # numerical parts
        for @parts -> $p {
            if $p ~~ /^\d+$/ { # Int {
                # assign to the serial part ($n, NOT a Num)
                # separate parts with periods
                $n ~= '.' if $n;
                $n ~= $p;
                # save the integers for later use
                @c.push: $p;
            }
            elsif $p ~~ Str {
                # assign to the string part ($s)
                # separate parts with spaces
                $s ~= ' ' if $s;
                $s ~= $p;
            }
            else {
                die "FATAL: Version part '$p' is not an Int nor a Str";
            }
        }
        my $vname   = $s; # don't downcase here.lc;
        # extract the short name
        my $vshort = $vname.lc;
        if $vshort {
            $vshort ~~ s:i/lts//;
            $vshort = $vshort.words.head;
        }
        
        my $vserial = $n; # 10, 11, 20.04.2, ...
        if not @c.elems {
            # not usual, but there is no serial part, so make it zero
            @c.push: 0;
            $vserial = 0;
        }

        # for numerical comparison
        # use the first two parts as is, for now add any third part to the
        # second by concatenation 
        my $vnum = @c.elems > 1 ?? (@c[0] ~ '.' ~ @c[1]) !! @c.head;
        if @c.elems > 2 {
            $vnum ~= @c[2];
        }

        # return the hash
        my %h = %(
            version-serial => $vserial,
            version-name   => $vname,
            vshort-name    => $vshort.lc,
            vnum           => $vnum.Num, # it MUST be a number
        );
        %h
    }
}

sub get-paths($dir = '.' --> Hash) is export {
    # Given any directory, recursively collect all files
    # and directories below it.
    my @todo = $dir.IO;
    my @fils;
    my @dirs;
    while @todo {
        for @todo.pop.dir -> $path {
            if $path.d {
                @todo.push: $path;
                @dirs.push: $path;
            }
            else {
                @fils.push: $path;
            }
        }
    }
    my %h = files => @fils, dirs => @dirs;
    %h
}
 
sub my-resources is export {
    %?RESOURCES
}

sub is-debian(--> Bool) {
    my $vnam = $*DISTRO.name.lc;
    $vnam eq 'debian';
}

sub is-ubuntu(--> Bool) {
    my $vnam = $*DISTRO.name.lc;
    $vnam eq 'ubuntu';
}

sub handle-prompt(:$res) is export {
    # $res is the return from a prompt asking
    # for a 'yes' response to take action or quit.
    if $res ~~ /^:i y/ {
        say "Proceeding...";
    }
    else {
        say "Exiting...";
        exit;
    }
}

sub set-rakudo-paths is export {
}

=begin comment
sub install-raku(:$debug) is export {
    my $dir = "/opt/rakudo-bin";
    if $dir.IO.d {
       say qq:to/HERE/;
       Directory '$dir' already exists. It must be removed first
       by the 'remove raku' mode.
       HERE
    }
    else {
       say "Directory '$dir' does not exist.";
       say "Installing 'rakudo-pkg'...";
    }
    my $os = OS.new;

    if $debug {
       print qq:to/HERE/;
       DEBUG: sub 'install-raku' is not yet usable...
       OS = {$os.name}
       version = {$os.version}
       number = {$os.vnum};
       nxadm's keyring location = {$os.keyring-location}
       HERE
    }

    if $os.name !~~ /:i debian / {
        say "FATAL: Only Debian can be handled for now.";
        say "       File an issue if you want another distro.";
        say "       Exiting.";
        exit;
    }
    say "Continuing...";

    if $os.name ~~ /:i debian / {
        shell "apt-get install -y debian-keyring";          # debian only
        shell "apt-get install -y debian-archive-keyring";  # debian only
    }
    if $os.name ~~ /:i debian|ubuntu / {
        shell "apt-get install -y apt-transport-https";
    }

    # only debian or ubuntu past here
    shell "curl -1sLf 'https://dl.cloudsmith.io/public/nxadm-pkgs/rakudo-pkg/gpg.0DD4CA7EB1C6CC6B.key' |  gpg --dearmor >> {$os.keyring-location}";

    shell "curl -1sLf 'https://dl.cloudsmith.io/public/nxadm-pkgs/rakudo-pkg/config.deb.txt?distro={$os.name}&codename={$os.version-name}' > /etc/apt/sources.list.d/nxadm-pkgs-rakudo-pkg.list";
    shell "apt-get update";
    shell "apt-get install rakudo-pkg";

    =begin comment
    set-sym-links();
    # take care of the PATH for all
    note "Log out and login to update your path for 'raku' to be found";
    note "Use this program to install 'zef'":
    note "Installation of raku via rakudo-pkg is complete";
    note "Removal of OS package 'rakudo' is complete";
    =end comment

    # add path info to /etc/profile.d/rakudo-pkg.sh
    my $f = "/etc/profile.d/rakudo-pkg.sh";
    my $rpath = q:to/HERE/;
    RAKUDO_PATHS=/opt/rakudo-pkg/bin:/opt/rakudo-pkg/share/perl6/bin:/
    if ! echo "$PATH" | /bin/grep -Eq "(^|:)$RAKUDO_PATHS($|:)" ; then
        export PATH="$PATH:$RAKUDO_PATHS"
    fi
    HERE
    if not $f.IO.f {
        say "Adding new PATH component in file '$f'...";
        spurt $f, $rpath;   
    }
    else {
        # dang!
    }

} # sub install-raku
=end comment

sub remove-raku() is export {
    my $dir = "/opt/rakudo-pkg";
    my $pkg = "rakudo-pkg";
    if $dir.IO.d {
        my $res = prompt "You really want to remove directory '$dir' (y/N)? ";
        if $res ~~ /^:i y/ {
            say "Proceeding...";
        }
        else {
            say "Exiting...";
            exit;
        }

        # first remove any symlinks to avoid dangling links
        # DO NOT USE manage-symlinks :delete;

        shell "apt-get remove rakudo-pkg";
        shell "rm -rf $dir" if $dir.IO.d;
        say "Package '$pkg' and directory '$dir' have been removed.";
        # rm any rakudo-pkg.sh in /etc/profile.d
        my $rfil = "/etc/profile.d/rakudo-pkg.sh";
        if $rfil.IO.f {
            shell "rm -f $rfil";
            say "File '$rfil' has been removed."
        }
    }
    else {
        say "Directory '$dir' does not exist!";
    }
}

sub install-path(:$user, :$restore, :$debug) is export {
    # $user is 'root' or other valid user name.
    my $home;
    if $user eq 'root' {
        $home = "/root";
    }
    else {
        $home = "/home/$user";
    }

    # Files needing changing or updating on Debian for Bash users:
    # We add a couple of lines as an embedded Bash action
    # based on the RAKUDO_PKG script:
    # except: put the rakudo-pkg path 
    # script in FRONT of the existing $PATH
    #=begin comment
    my $rpath = q:to/HERE/;
    RAKUDO_PATHS=/opt/rakudo-pkg/bin:/opt/rakudo-pkg/share/perl6/bin:/
    if ! echo "$PATH" | /bin/grep -Eq "(^|:)$RAKUDO_PATHS($|:)" ; then
        #export PATH="$PATH:$RAKUDO_PATHS"
        export PATH="$RAKUDO_PATHS:$PATH"
    fi
    HERE
    #=end comment

    # Affected files
    # For all users:
    my $a1 = "/etc/bash.bashrc";
    my $a2 = "/etc/profile";
    my $a3 = "/etc/profile.d/rakudo-pkg.sh";

    # Particular users:
    my $u1 = "{$home}/.bashrc";
    my $u2 = "{$home}/.profile";
    my $u3 = "{$home}/.bash_aliases";
    my $u4 = "{$home}/.bash_profile";
    my $u5 = "{$home}/.xsessionrc";

    for $u1, $u2, $u3, $u4, $u5 -> $f {
        handle-path-file $f, :$user, :$restore, :$debug;
    }
    return if $user ne "root";

    for $a1, $a2, $a3 -> $f {
        handle-path-file $f, :$user, :$restore, :$debug;
    }
}

sub handle-path-file($f, :$user, :$restore, :$debug) is export {
    # For each file:
    #   does it exist yet?
    #   is it original? (it would have a '$f.orig' version in the same directory)
    #   has it been modified? (it would have a line with RAKUDO on it)
    #   shall we restore it to its original form (possibly empty or non-existent)
    my $exists  = $f.IO.f ?? True !! False;   
    if not $exists {
        say "  Creating non-existent file: $f";
        spurt $f, "";
        $exists = True;
    }

    my $is-orig = "$f.orig".IO.f ?? False !! True;   
    my @lines = $f.IO.lines;
    if $debug {
        say "  Inspecting file '$f'";
        =begin comment
        say "    Contents:";
        say "      $_" for @lines;
        say "    End contents for file '$f'";
        =end comment
        my $tag = "RAKUDO_PATHS";
        for @lines.kv -> $i, $line {
            if $line ~~ /$tag/ {
                say "    Found $tag on line {$i+1}";
            }
        }
        say "    Is it original? $is-orig";
        say "    Number of lines: {@lines.elems}";
    }
    if $is-orig {
        # make a copy
         copy $f, "$f.orig";
    }

    # check for and add missing lines to certain files:
    #   .bash_profile
    #   .xsessionrc
    return unless $f ~~ /\. bash_profile|xsessionrc /;

    my $a = q:to/HERE/;
    if [ -f ~/.profile ]; then
        . ~/.profile 
    fi
    HERE

    my $b = q:to/HERE/;
    if [ -f ~/.bashrc ]; then
        . ~/.bashrc 
    fi
    HERE
    
    my $mlines = 0; # checking for three matching lines
    for @lines {
    }


}

sub get-backup-name($f, :$use-date --> Str) is export {
    # Given a file name, return a backup name consisting
    # of the original name with either '.orig' appended
    # or the current time in format '.YYYY-MM-DDThh:mm:ssZ'.
    my $nam;
    if $use-date {
        my $dt = DateTime.now: :timezone(0);
        my $y = sprintf "%02d", $dt.year;
        my $M = sprintf "%02d", $dt.month;
        my $d = sprintf "%02d", $dt.day;
        my $h = sprintf "%02d", $dt.hour;
        my $m = sprintf "%02d", $dt.minute;
        my $s = sprintf "%02d", $dt.second;
        $nam = "{$f}.{$y}-{$M}-{$d}T{$h}{$m}.{$s}Z";
     }
     else {
        $nam = "{$f}.orig";
     }
     $nam
}

sub download-rakudo-bin(
    :$date! where {/^ \d**4 '-' \d\d $/}, 
    :OS(:$os)!, 
    :$spec, 
    :$release is copy where { /^ \d+ $/ } = 1,
    :$debug,
    ) is export {

    my $dotted-date = $date;
    $dotted-date ~~ s/'-'/./;
    my $err;
    my ($sys, $arch, $tool, $type);
    if $os ~~ /:i lin/ {
        $sys = "linux";
        $arch = "x86_64";
        $tool = "gcc";
        $type = "tar.gz";
    }
    elsif $os ~~ /:i win/ {
        $sys = "win";
        $arch = "x86_64";
        $tool = "msvc";
        $type = "msi"; # default, else "zip" if $spec.defined
    }
    elsif $os ~~ /:i mac/ {
        $sys = "macos";
        $tool = "clang";
        $arch = "arm64"; # default, else "x86_64" if $spec.defined
        $type = "tar.gz";
    }
    else {
        say "FATAL: Unrecgnized OS '$os'. Try 'lin', 'win', or 'mac'.";
        exit;
    }
    if 29 < $release < 1 {
        say "FATAL: Release must be between 1 and 29. You entered '$release'.":
        exit;
    }

    if $spec.defined {
        $arch = "x86_84" if $os eq "macos";
        $type = "zip" if $os eq "win";
    }

    $release = sprintf "%02d", $release;
   
    # final download file name              backend
    #                                            date    release
    #                                                       sys   arch   tool
    #                                                       sys   arch       type 
    #   https://rakudo.org/dl/rakudo/rakudo-moar-2023.09-01-linux-x86_64-gcc.tar.gz
    #                                                             spec=arch
    #   https://rakudo.org/dl/rakudo/rakudo-moar-2023.09-01-macos-arm64-clang.tar.gz
    #   https://rakudo.org/dl/rakudo/rakudo-moar-2023.09-01-macos-x86_64-clang.tar.gz
    #                                                                       spec=type
    #   https://rakudo.org/dl/rakudo/rakudo-moar-2023.09-01-win-x86_64-msvc.msi
    #   https://rakudo.org/dl/rakudo/rakudo-moar-2023.09-01-win-x86_64-msvc.zip
    #   
    #   "https://rakudo.org/dl/rakudo/rakudo-moar-{$date}-{$release}-{$os}-{$arch}-{$tool}.{$type}";
    #       plus a C<.asc> and C<.checksums.txt> extensions.

    # actual download file basename on the remote site:
    my $inbase  = "rakudo-moar-{$dotted-date}-{$release}-{$sys}-{$arch}-{$tool}.{$type}";

    # directory basename to unpack the archive in:
    # final location of the archive
    my $rak-dir = "/opt/rakudo-{$date}-{$release}";
    if $rak-dir.IO.d {
        say "WARNING: Rakudo directory '$rak-dir' exists.";
        my $res = prompt "  Do you want to delete it (y/N)? ";
        if $res ~~ /:i y/ {
            say "  Okay, deleting the directory...";
            shell "rm -rf $rak-dir";
        }
        else {
            say "  Okay, aborting installation.";
            exit;
        }
    }

    my $filebase = "rakudo-{$date}-{$release}.{$type}";

    # remote download directory
    my $remote-dir = "https://rakudo.org/dl/rakudo";

    # files to download:
    my $r-archive = "{$remote-dir}/{$inbase}";
    my $r-asc     = "{$remote-dir}/{$inbase}.asc";
    my $r-check   = "{$remote-dir}/{$inbase}.checksums.txt";

    # files renamed upon download to:
    my $f-archive = "{$filebase}";
    my $f-asc     = "{$filebase}.asc";
    my $f-check   = "{$filebase}.checksums.txt";

    # I want to rename the files as they download
    shell "curl -1sLf $r-archive -o $f-archive";
    shell "curl -1sLf $r-asc     -o $f-asc";
    shell "curl -1sLf $r-check   -o $f-check";

    print qq:to/HERE/;
    See downloaded files:
        $f-archive
        $f-asc
        $f-check

    Checking binary validity...
    HERE

    verify-checksum $f-check;

    say "Checking signature...";
    verify-signature $f-check;

    =begin comment
    #shell "curl -1sLf '$archive'";
    # -1 - use TLS 1 or higher
    # -s - silent
    # -L - follow redirects
    # -f - fail quickly with first error
    # save to same name, use -O
    shell "curl -OL $archive";
    # save to different name, use -o
    shell "curl -L1sf -o $desired-name $archive";
    =end comment

}

sub verify-checksum($fcheck) is export {
    # To verify that a downloaded file is not corrupted, 
    # download the *.checksums.txt corresponding to the 
    # download you want to verify. Then run
    #
    #    $ sha256 -c file_you_downloaded
    #
    # WRONG format for Debian:
    # pertinent line in the checksums file, not in standard format:
    #   SHA256 (rakudo-moar-2023.09-01-linux-x86_64-gcc.tar.gz) = 44ec... (sha256 hash)
    # shell "sha256sum -c $fcheck";

    # reformat it to:  the-check-sum file-name
    #
    # get the hash from the existing file
    my $sha;
    for $fcheck.IO.lines -> $line is copy {
        next unless $line ~~ /:i sha256 /;
        # elim parens
        $line ~~ s/'('//;
        $line ~~ s/')'//;
        my @w = $line.words;
        $sha  = @w[3];
        last;
    }
    my $fnam = $fcheck;
    my $fcheck-new = $fcheck;
    $fnam ~~ s/\.checksums\.txt//;
    $fcheck-new ~~ s/checksums\.txt/sha256sum/;

    spurt $fcheck-new, "$sha $fnam";
    shell "sha256sum -c $fcheck-new";
}

sub verify-signature($fcheck) is export {
    # In addition one can verify the download is authentic 
    # by checking its signature. One can validate the 
    # checksum file which contains a self contained signature.
    # To verify via the checksum file do
    #
    #    $ gpg2 --verify file_you_downloaded.checksums.txt
    # shell "gpg --verify $fcheck";

    # we are going to read the signature and compare it with known Github
    # keys from our releasers
}

sub set-path() is export {
    # sets the path for the rakudo-bin installation
    # the path must come BEFORE
}

