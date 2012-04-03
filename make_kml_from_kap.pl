
use strict;

$| = 1;


my @charts;
my %chartsByScale;


while (my $kap = <*.kap>) {

	my $name = $kap;
	$name =~ s/\.kap$//i;
	$name =~ s/^.*\///;

	print "Reading $kap\n";

	open KAP, $kap or die $!;

	my $scale;
	my $width;
	my $height;

	my $ref1;
	my $ref2;
	my $ref3;

	for (1..100) {
	    my $line = <KAP>;

	    if ( $line =~ /^KNP\/SC=(\d+)/ ) {
	    	$scale = $1;
	    }

	    if ( $line =~ /RA=(\d+),(\d+)/ ) {
		$width = $1;
		$height = $2;
	    }

	    if ( $line =~ /REF\/1,(\d+),(\d+),(\d+\.\d+),(\d+\.\d+)/ ) {
		$ref1->{x}    = $1;
		$ref1->{y}    = $2;
		$ref1->{lat}  = $3;
		$ref1->{long} = $4;
	    }

	    if ( $line =~ /REF\/2,(\d+),(\d+),(\d+\.\d+),(\d+\.\d+)/ ) {
		$ref2->{x}    = $1;
		$ref2->{y}    = $2;
		$ref2->{lat}  = $3;
		$ref2->{long} = $4;
	    }

	    if ( $line =~ /REF\/3,(\d+),(\d+),(\d+\.\d+),(\d+\.\d+)/ ) {
		$ref3->{x}    = $1;
		$ref3->{y}    = $2;
		$ref3->{lat}  = $3;
		$ref3->{long} = $4;
	    }

	}

	close KAP;

	print "Scale: $scale\n";
	print "Width: $width\n";
	print "Height: $height\n";
	print "\n";

	print "Ref1 x: $ref1->{x}\n";
	print "Ref1 y: $ref1->{y}\n";
	print "Ref1 lat: $ref1->{lat}\n";
	print "Ref1 long: $ref1->{long}\n";
	print "\n";

	print "Ref2 x: $ref2->{x}\n";
	print "Ref2 y: $ref2->{y}\n";
	print "Ref2 lat: $ref2->{lat}\n";
	print "Ref2 long: $ref2->{long}\n";
	print "\n";

	print "Ref3 x: $ref3->{x}\n";
	print "Ref3 y: $ref3->{y}\n";
	print "Ref3 lat: $ref3->{lat}\n";
	print "Ref3 long: $ref3->{long}\n";
	print "\n";



	my $xmin;
	my $xmax;
	my $ymin;
	my $ymax;

	foreach my $ref ($ref1, $ref2, $ref3) {
	    $xmin = $ref if ( !defined $xmin or $ref->{x} < $xmin->{x} );
	    $xmax = $ref if ( !defined $xmax or $ref->{x} > $xmax->{x} );
	    $ymin = $ref if ( !defined $ymin or $ref->{y} < $ymin->{y} );
	    $ymax = $ref if ( !defined $ymax or $ref->{y} > $ymax->{y} );
	}

	print "xmin x: $xmin->{x}\n";
	print "xmin y: $xmin->{y}\n";
	print "xmin lat: $xmin->{lat}\n";
	print "xmin long: $xmin->{long}\n";
	print "\n";

	print "xmax x: $xmax->{x}\n";
	print "xmax y: $xmax->{y}\n";
	print "xmax lat: $xmax->{lat}\n";
	print "xmax long: $xmax->{long}\n";
	print "\n";

	print "ymin x: $ymin->{x}\n";
	print "ymin y: $ymin->{y}\n";
	print "ymin lat: $ymin->{lat}\n";
	print "ymin long: $ymin->{long}\n";
	print "\n";

	print "ymax x: $ymax->{x}\n";
	print "ymax y: $ymax->{y}\n";
	print "ymax lat: $ymax->{lat}\n";
	print "ymax long: $ymax->{long}\n";
	print "\n";



	my $longPerPixel = ($xmax->{long} - $xmin->{long}) / ($xmax->{x} - $xmin->{x});
	my $latPerPixel  = ($ymax->{lat}  - $ymin->{lat})  / ($ymax->{y} - $ymin->{y});

	print "longPerPixel: $longPerPixel\n";
	print "latPerPixel: $latPerPixel\n";
	print "\n";


	my $north = $ymin->{lat}  - ($ymin->{y} * $latPerPixel);
	my $south = $ymax->{lat}  + (($height - $ymax->{y}) * $latPerPixel);
	my $east  = $xmax->{long} + (($width - $xmax->{x}) * $longPerPixel);
	my $west  = $xmin->{long} - ($xmin->{x} * $longPerPixel);


	push @charts => {
	    name  => $name,
	    scale => $scale,
	    north => $north,
	    south => $south,
	    east  => $east,
	    west  => $west,
	};

	push @{ $chartsByScale{$scale} } => $charts[-1];

	print "north: $north\n";
	print "south: $south\n";
	print "east: $east\n";
	print "west: $west\n";
	print "\n";

	print "\n";
}



my %drawOrderByScale;
my $scaleDrawOrder = 0;
foreach my $scale (sort {$b <=> $a} keys %chartsByScale) {
    $drawOrderByScale{$scale} = ++$scaleDrawOrder * 10;
}


foreach my $chart (@charts) {
    my $drawOrder = $drawOrderByScale{$chart->{scale}};

    open KML, '>', "$chart->{name}.kml" or die $!;
    print KML <<END;
<?xml version="1.0" encoding="iso-8859-1"?>
<kml xmlns="http://earth.google.com/kml/2.1">
    <Document>
	<name>$chart->{name}</name>
	<GroundOverlay>
	    <name>$chart->{name}</name>
	    <drawOrder>$drawOrder</drawOrder>
	    <Icon>
		<href>../png16m_smooth/$chart->{name}.png</href>
	    </Icon>
	    <LatLonBox>
		<north>$chart->{north}</north>
		<south>$chart->{south}</south>
		<west>$chart->{west}</west>
		<east>$chart->{east}</east>
	    </LatLonBox>
	</GroundOverlay>
    </Document>
</kml>
END
    close KML;
}









open KML, '>', 'index.kml' or die $!;

print KML <<END;
<?xml version="1.0" encoding="iso-8859-1"?>
<kml xmlns="http://earth.google.com/kml/2.1">
<Document>
    <name>Svenska sjökort</name>
END

foreach my $scale (sort {$b <=> $a} keys %chartsByScale) {

    print KML <<END;
    <Folder>
	<name>1:$scale</name>
END
    foreach my $chart (sort { $a->{name} cmp $b->{name} } @{ $chartsByScale{$scale} } ) {
	print KML <<END;
	<NetworkLink>
	    <name>$chart->{name}</name>
	    <Region>
		<LatLonAltBox>
		    <north>$chart->{north}</north>
		    <south>$chart->{south}</south>
		    <west>$chart->{west}</west>
		    <east>$chart->{east}</east>
		</LatLonAltBox>
		<Lod>
		    <minLodPixels>128</minLodPixels>
		    <maxLodPixels>-1</maxLodPixels>
		</Lod>
	    </Region>
	    <Link>
		<href>$chart->{name}.kml</href>
		<viewRefreshMode>onRegion</viewRefreshMode>
	    </Link>
	</NetworkLink>
END
	}
    print KML <<END;
    </Folder>
END
    }


print KML <<END;
    </Document>
</kml>
END

close KML;

