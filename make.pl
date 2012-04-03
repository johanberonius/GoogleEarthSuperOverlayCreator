
use strict;

while (<*.kml>) {
    my $name = $_;
    my $path = $name;
    $path =~ s/\.kml$//i;

    my $cmd = qq(perl GoogleEarthSuperOverlayCreator.pl --debug --size=512 --path="$path" "$name" 2>"$path.log");
    print $cmd, "\n";
    print qx($cmd);
}
