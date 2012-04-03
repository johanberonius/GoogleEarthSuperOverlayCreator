#!perl

use strict;
use Getopt::Long;
use POSIX qw(ceil);
use Unicode::String qw(utf8 latin1);

eval "use Image::Size;";
die <<END if $@;
$0 requires Image::Size module.

If you are using ActivePerl, please install using:

'ppm install Image-Size'
END

eval "use XML::LibXML ();";
die <<END if $@;
$0 requires XML::LibXML module.

If you are using ActivePerl, please install using:

'ppm install http://theoryx5.uwinnipeg.ca/ppms/XML-LibXML-Common.ppd'
'ppm install http://theoryx5.uwinnipeg.ca/ppms/XML-LibXML.ppd'
END

die <<END unless qx(convert 2>&1) =~ /ImageMagick/i;
$0 requires ImageMagick.

Please download and install from http://imagemagick.org/
Also make sure your PATH environment variable is set correctly.
END

my $inputImage;
my $tileBaseName;
my $debug;
my $outputPath = '.';
my $outputImageType = 'jpg';
my $outputImageQuality = 88;
my $tileSize  = 1024;
my $baseDrawOrder = 0;

my ($north, $south, $west, $east);
my $longPerPixel;
my $latPerPixel;


GetOptions ("image=s"     => \$inputImage,
	    "name=s"      => \$tileBaseName,
	    "path=s"      => \$outputPath,
	    "type=s"      => \$outputImageType,
	    "quality=s"   => \$outputImageQuality,
	    "size=s"      => \$tileSize,
	    "draworder=n" => \$baseDrawOrder,
	    "debug"       => \$debug);

my $inputKmlFile = $ARGV[0];

my $usage =<<END;
Usage: $0 [OPTIONS] FILE

  Creates a Super Overlay for Google Earth by dividing an image into smaller tiles
  and writing necessary KML-files.

  FILE should be a KML-file that contains a GroundOverlay tag that specifies the
  source image and its coordinates.
  Example:

  <?xml version="1.0" encoding="iso-8859-1"?>
  <kml xmlns="http://earth.google.com/kml/2.1">
    <GroundOverlay>
      <name>Base name</name>
      <drawOrder>0</drawOrder>
      <Icon>
        <href>image.png</href>
      </Icon>
      <LatLonBox>
        <north>59.4607614099377</north>
        <south>59.2839926519017</south>
        <west>18.0395238098571</west>
        <east>18.5313536923417</east>
      </LatLonBox>
    </GroundOverlay>
  </kml>

  Alternatively the KML-file could contain two Placemarks for two knows coordinates.
  The x and y coordinates in the original image must be specified in the description.
  The --image option must be used.

  Example:

  <?xml version="1.0" encoding="iso-8859-1"?>
  <kml xmlns="http://earth.google.com/kml/2.1">
    <Document>
      <name>Base name</name>
      <Placemark>
        <description>123,456</description>
        <Point>
          <coordinates>18.08541713675965,59.37609854061633,0</coordinates>
        </Point>
      </Placemark>
      <Placemark>
        <description>123,456</description>
        <Point>
          <coordinates>18.18541713675965,59.47609854061633,0</coordinates>
        </Point>
      </Placemark>
    </Document>
  </kml>



Options:
  --image=file       Source image to use. If not specified the Icon href of the
                     GroundOverlay is used. Required if a KML-file with Placemarks
                     is used.

  --name=string      Base name to use for all files. If not specified the name of the
                     Document or GroundOverlay in the KML is used. If that is not found
                     the image name without the extension is used.

  --path=path        Output directory where images and KML-files are written.
                     Default is current directory.

  --type=extension   Type to use for all genereted images. Eg. 'png', 'tif', 'gif', 'jpg'.
                     Default is '$outputImageType'.

  --quality=number   Image quality used if type is 'jpg'.
                     Value between 1 and 100. Default is $outputImageQuality.

  --size=number      Size used for tiles. Must be a power of two, eg. 256, 512, 1024.
                     Default is $tileSize.

  --draworder=number Base drawOrder to use for all GroundOverlays. This number will be
                     incremented for each level to make sure higher detail images are
                     drawn on top. If not specified the drawOrder of the GroundOverlay
                     in the input KML-file is used.

  --debug            Print debug messages

END

die $usage unless $inputKmlFile;
die "KML-file doesn't exist: $inputKmlFile\n" unless -e $inputKmlFile;
warn "Reading $inputKmlFile\n" if $debug;



my %powerOfTwo = map {2**$_ => 'true'} (8..12);
die "Size must be a power of two between 256 and 4096: $tileSize\n" unless $powerOfTwo{$tileSize};


# Create an XML parser and create a prefix for the default namespace
my $kmlDoc = XML::LibXML->new()->parse_file($inputKmlFile);
my $docNS = $kmlDoc->documentElement()->namespaceURI();
$kmlDoc->documentElement()->setNamespace($docNS, 'kml');


# If inputImgage is not set look if the GroundOverlay has a icon and use that
$inputImage ||= utf8($kmlDoc->findvalue('//kml:GroundOverlay[1]/kml:Icon/kml:href'))->latin1;
die "Source image is required.\n" unless $inputImage;
die "Source image doesn't exist: $inputImage\n" unless -e $inputImage;


# If tileBaseName is not set look if the GroundOverlay has a name and use that
$tileBaseName ||= utf8($kmlDoc->findvalue('//kml:GroundOverlay[1]/kml:name'))->latin1;
$tileBaseName ||= utf8($kmlDoc->findvalue('//kml:Document[1]/kml:name'))->latin1;

# If tileBaseName is still not set, use image name without the extension
unless ($tileBaseName) {
    $tileBaseName = $inputImage;
    $tileBaseName =~ s/\.\w+$//;
}

$baseDrawOrder ||= $kmlDoc->findvalue('//kml:GroundOverlay[1]/kml:drawOrder') || 0;

mkdir $outputPath or die "Can't create output path: $outputPath, $!\n" unless -d $outputPath;


my ($inputWidth, $inputHeight) = imgsize($inputImage);
die "Can't get image dimensions for: $inputImage, $!\n" unless $inputWidth && $inputHeight;



if (my @overlays = $kmlDoc->findnodes('//kml:GroundOverlay[1]')) {

    $north = $overlays[0]->findvalue('./kml:LatLonBox/kml:north');
    $south = $overlays[0]->findvalue('./kml:LatLonBox/kml:south');
    $west  = $overlays[0]->findvalue('./kml:LatLonBox/kml:west');
    $east  = $overlays[0]->findvalue('./kml:LatLonBox/kml:east');
    die "Can't find coordinates for GroundOverlay\n" unless ($north && $south && $west && $east);

    $latPerPixel  = ($south - $north) / $inputHeight;
    $longPerPixel = ($east - $west) / $inputWidth;

} elsif (my @placemarks = $kmlDoc->findnodes('//kml:Placemark')) {

    my $desc1 = $placemarks[0]->findvalue('./kml:description');
    my ($p1x, $p1y) = $desc1 =~ /\D*(\d+)\D+(\d+)/;
    die "Can't find original image coordinates in Placemark description.\n" unless $p1x && $p1y;

    my $coord1 = $placemarks[0]->findvalue('./kml:Point/kml:coordinates');
    my ($p1long, $p1lat) = split /\s*,\s*/, $coord1;
    die "Can't find coordinates for Placemark.\n" unless $p1lat && $p1long;

    my $desc2 = $placemarks[1]->findvalue('./kml:description');
    my ($p2x, $p2y) = $desc2 =~ /\D*(\d+)\D+(\d+)/;
    die "Can't find original image coordinates in Placemark description.\n" unless $p2x && $p2y;

    my $coord2 = $placemarks[1]->findvalue('./kml:Point/kml:coordinates');
    my ($p2long, $p2lat) = split /\s*,\s*/, $coord2;
    die "Can't find coordinates for Placemark.\n" unless $p2lat && $p2long;

    $latPerPixel  = ($p1lat  - $p2lat)  / ($p1y - $p2y);
    $longPerPixel = ($p1long - $p2long) / ($p1x - $p2x);

    $north = $p1lat  - $p1y * $latPerPixel;
    $west  = $p1long - $p1x * $longPerPixel;

} else {
    die "No GroundOverlay or Placemarks found in the KML-file.\n";
}




my $tiles  = 1;
my $level = 1;

warn "Processing $inputImage\n" if $debug;
warn "Image dimensions: $inputWidth x $inputHeight\n" if $debug;
warn "\n" if $debug;

while (1) {
    warn "Generating level: $level\n" if $debug;

    my $resize = $tiles * $tileSize;

    my $isLastLevel     = $resize * 2 >= $inputWidth &&
                          $resize * 2 >= $inputHeight;

    my $originalTileSize = $tileSize;
    if ($isLastLevel) {
	$resize = $inputWidth > $inputHeight ? $inputWidth : $inputHeight;
	$tileSize = ceil($resize / $tiles);
    }

    my $resizeWidth   = $resize;
    my $resizeHeight  = $resize;

    if ($inputWidth > $inputHeight) {
	$resizeHeight = $inputHeight * $resizeWidth / $inputWidth;
    } elsif ($inputHeight > $inputWidth) {
	$resizeWidth  = $inputWidth  * $resizeHeight / $inputHeight;
    }

    my $horizontalTiles = ceil($resizeWidth  / $tileSize);
    my $verticalTiles   = ceil($resizeHeight / $tileSize);
    my $scale           = $inputWidth / $resizeWidth;

    warn "Resized dimensions: $resizeWidth x ". int($resizeHeight) ."\n" if $debug;
    warn "Downscale factor: $scale\n" if $debug;
    warn "Number of tiles: $horizontalTiles x $verticalTiles\n" if $debug;




    my $allImagesExists = 1;
    CheckExist:
    for (my $yi = 0; $yi < $verticalTiles; $yi++) {
	for (my $xi = 0; $xi < $horizontalTiles; $xi++) {
	    my $tileFilename = "$tileBaseName-$level-$yi-$xi.$outputImageType";
	    if ( -e "$outputPath/$tileFilename") {
		warn "Tile image already exists: $outputPath/$tileFilename\n" if $debug;
	    } else {
		$allImagesExists = 0;
		last CheckExist;
	    }
	}
    }


    unless ($allImagesExists) {
	my $imgTileName    = $level == 1  ? '-0' : '';
	my $cropCommand    = $level == 1  ? ''   : "-crop ${tileSize}x${tileSize}";
	my $resizeCommand  = $isLastLevel ? ''   : qq(-resize "${resize}x${resize}>");
	my $qualityCommand = $outputImageType eq 'jpg' ? "-quality $outputImageQuality" : '';
	my $command = qq(convert  "$inputImage" $resizeCommand $cropCommand $qualityCommand "$outputPath/$tileBaseName-$level$imgTileName.$outputImageType");
	warn qq($command \n) if $debug;
        my $outp = `$command`;
        warn $outp if $outp && $debug;
    } else {
	warn "All tile images already exists, skipping image conversion.\n" if $debug;
    }


    my $tileNumber = 0;
    for (my $y = 0, my $yi = 0; $y < $resizeHeight; $y += $tileSize, $yi++) {
	for (my $x = 0, my $xi = 0; $x < $resizeWidth; $x += $tileSize, $xi++, $tileNumber++) {

	    my $x1 = $x * $scale;
	    my $x2 = ($x + $tileSize) * $scale;
	    my $xmid = ($x1 + $x2) / 2;
	    $x1 = $inputWidth if $x1 > $inputWidth;
	    $x2 = $inputWidth if $x2 > $inputWidth;

	    my $y1 = $y * $scale;
	    my $y2 = ($y + $tileSize) * $scale;
	    my $ymid = ($y1 + $y2) / 2;
	    $y1 = $inputHeight if $y1 > $inputHeight;
	    $y2 = $inputHeight if $y2 > $inputHeight;

	    my $tileNumberFilename = "$tileBaseName-$level-$tileNumber.$outputImageType";
	    my $tileFilename       = "$tileBaseName-$level-$yi-$xi.$outputImageType";

	    if ( -e "$outputPath/$tileNumberFilename") {
		rename "$outputPath/$tileNumberFilename" => "$outputPath/$tileFilename" or die "Can't rename $outputPath/$tileNumberFilename to $outputPath/$tileFilename, $!\n";
	    }
	    unless ( -e "$outputPath/$tileFilename") {
		warn "Tile image doesn't exist: $outputPath/$tileFilename\n";
		next;
	    }

	    my ($tileHeight, $tileWidth) = imgsize("$outputPath/$tileFilename");
	    my $areaSqrt = sqrt($tileHeight * $tileWidth);

	    if ($isLastLevel) {
		my $otw = $originalTileSize;
		my $oth = $originalTileSize;
		if ($tileWidth > $tileHeight) {
		    $oth = $tileHeight * $originalTileSize / $tileSize;
		} elsif ($tileHeight > $tileWidth) {
		    $otw  = $tileWidth * $originalTileSize / $tileSize;
		}
		$areaSqrt = sqrt($otw * $oth);
	    }

	    my $tileWest = $west + $x1 * $longPerPixel;
	    my $tileEast = $west + $x2 * $longPerPixel;
	    my $tileMidLong = $west + $xmid * $longPerPixel;

	    my $tileNorth = $north + $y1 * $latPerPixel;
	    my $tileSouth = $north + $y2 * $latPerPixel;
	    my $tileMidLat = $north + $ymid * $latPerPixel;

	    my $drawOrder = $baseDrawOrder + $level;

	    my $minLodPixels     = int( $level == 1  ? $areaSqrt / 8 : $areaSqrt / 1.6 );
	    my $maxLodPixels     = int( $isLastLevel ?            -1 : $areaSqrt * 1.75 );
	    my $minFadeExtent    = int( $level == 1  ? $areaSqrt / 16 : $areaSqrt / 12 );
	    my $maxFadeExtent    = int($areaSqrt / 6);
	    my $linkMinLodPixels = int($areaSqrt / 1.6);

	    my $kmlFilename = $level == 1  ? "$tileBaseName.kml" : "$tileBaseName-$level-$yi-$xi.kml";

	    warn "Tile number: $tileNumber\n" if $debug;
	    warn "Tile dimensions: $tileHeight x $tileWidth\n" if $debug;
	    warn "Tile coordinates: $xi x $yi\n" if $debug;
	    warn "Coordinates in original image: x$x1-$x2 y$y1-$y2\n" if $debug;
	    warn "Writing KML file: $kmlFilename\n" if $debug;

	    open KML, '>', "$outputPath/$kmlFilename" or die $!;
	    print KML <<END;
<?xml version="1.0" encoding="iso-8859-1"?>
<kml xmlns="http://earth.google.com/kml/2.1">
    <Document>
	<name>$kmlFilename</name>
	<GroundOverlay>
	    <name>$tileFilename</name>
	    <Region>
		<LatLonAltBox>
		    <north>$tileNorth</north>
		    <south>$tileSouth</south>
		    <west>$tileWest</west>
		    <east>$tileEast</east>
		</LatLonAltBox>
		<Lod>
		    <minLodPixels>$minLodPixels</minLodPixels>
		    <maxLodPixels>$maxLodPixels</maxLodPixels>
		    <minFadeExtent>$minFadeExtent</minFadeExtent>
		    <maxFadeExtent>$maxFadeExtent</maxFadeExtent>
		</Lod>
	    </Region>
	    <drawOrder>$drawOrder</drawOrder>
	    <Icon>
		<href>$tileFilename</href>
	    </Icon>
	    <LatLonBox>
		<north>$tileNorth</north>
		<south>$tileSouth</south>
		<west>$tileWest</west>
		<east>$tileEast</east>
	    </LatLonBox>
	</GroundOverlay>
END

	    my $nextLevel = $level + 1;
	    my $sub0tileNumber = ($yi * 2)     . '-'. ($xi * 2);
	    my $sub1tileNumber = ($yi * 2)     . '-'. ($xi * 2 + 1);
	    my $sub2tileNumber = ($yi * 2 + 1) . '-'. ($xi * 2);
	    my $sub3tileNumber = ($yi * 2 + 1) . '-'. ($xi * 2 + 1);

	    print KML <<END unless $isLastLevel;
	<NetworkLink>
	    <name>$tileBaseName-$nextLevel-$sub0tileNumber.kml</name>
	    <Region>
		<LatLonAltBox>
		    <north>$tileNorth</north>
		    <south>$tileMidLat</south>
		    <west>$tileWest</west>
		    <east>$tileMidLong</east>
		</LatLonAltBox>
		<Lod>
		    <minLodPixels>$linkMinLodPixels</minLodPixels>
		    <maxLodPixels>-1</maxLodPixels>
		</Lod>
	    </Region>
	    <Link>
		<href>$tileBaseName-$nextLevel-$sub0tileNumber.kml</href>
		<viewRefreshMode>onRegion</viewRefreshMode>
	    </Link>
	</NetworkLink>
END
	    print KML <<END unless $tileMidLong > $tileEast or $isLastLevel;
	<NetworkLink>
	    <name>$tileBaseName-$nextLevel-$sub1tileNumber.kml</name>
	    <Region>
		<LatLonAltBox>
		    <north>$tileNorth</north>
		    <south>$tileMidLat</south>
		    <west>$tileMidLong</west>
		    <east>$tileEast</east>
		</LatLonAltBox>
		<Lod>
		    <minLodPixels>$linkMinLodPixels</minLodPixels>
		    <maxLodPixels>-1</maxLodPixels>
		</Lod>
	    </Region>
	    <Link>
		<href>$tileBaseName-$nextLevel-$sub1tileNumber.kml</href>
		<viewRefreshMode>onRegion</viewRefreshMode>
	    </Link>
	</NetworkLink>
END
	    print KML <<END unless $tileMidLat < $tileSouth or $isLastLevel;
	<NetworkLink>
	    <name>$tileBaseName-$nextLevel-$sub2tileNumber.kml</name>
	    <Region>
		<LatLonAltBox>
		    <north>$tileMidLat</north>
		    <south>$tileSouth</south>
		    <west>$tileWest</west>
		    <east>$tileMidLong</east>
		</LatLonAltBox>
		<Lod>
		    <minLodPixels>$linkMinLodPixels</minLodPixels>
		    <maxLodPixels>-1</maxLodPixels>
		</Lod>
	    </Region>
	    <Link>
		<href>$tileBaseName-$nextLevel-$sub2tileNumber.kml</href>
		<viewRefreshMode>onRegion</viewRefreshMode>
	    </Link>
	</NetworkLink>
END
	    print KML <<END unless $tileMidLong > $tileEast or $tileMidLat < $tileSouth or $isLastLevel;
	<NetworkLink>
	    <name>$tileBaseName-$nextLevel-$sub3tileNumber.kml</name>
	    <Region>
		<LatLonAltBox>
		    <north>$tileMidLat</north>
		    <south>$tileSouth</south>
		    <west>$tileMidLong</west>
		    <east>$tileEast</east>
		</LatLonAltBox>
		<Lod>
		    <minLodPixels>$linkMinLodPixels</minLodPixels>
		    <maxLodPixels>-1</maxLodPixels>
		</Lod>
	    </Region>
	    <Link>
		<href>$tileBaseName-$nextLevel-$sub3tileNumber.kml</href>
		<viewRefreshMode>onRegion</viewRefreshMode>
	    </Link>
	</NetworkLink>
END
	    print KML <<END;
    </Document>
</kml>
END
	    close KML;
	}
    }
    warn "Number of tiles for level $level: $tileNumber\n" if $debug;
    warn "\n" if $debug;

    $tiles *= 2;
    $level++;

    last if $isLastLevel;
}

warn "Done!\n\n" if $debug;
