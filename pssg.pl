#!/usr/bin/env perl

use 5.012;
use strict;
use warnings;

use Getopt::Std;
use File::Find::Rule;
use File::Path;
use File::Spec;
use Text::Nimble;

sub print_help {
    print "pssg options\n";
    print "============\n";
    print "-c\tclean output directory\n";
    print "-h\thelp\n";
    print "-f\tinput directory\n";
    print "-m\tmacro file\n";
    print "-o\toutput directory\n";
    print "-s\tstyle sheet file\n";
}

sub render_html {
    my $infile  = shift(@_);
    my $outfile = shift(@_);
    my $nav     = shift(@_);
    my $styles  = shift(@_);
    my $macros  = shift(@_);

    my $pre = <<"END";
<!DOCTYPE html>
<html>
<head>
    <style>$styles</style>
</head>
<body>
$nav
END

    my $end = <<"END";
</body>
</html>
END

    print "[WRT ] Rendering file '$infile'...\n";
    open(my $fh, "<", $infile)
        or die "[ERR ] Can't open '$infile': $!";

    my $text;
    {
        local $/ = undef;
        $text    = <$fh>;
    }
    my $ast = Text::Nimble::parse($macros . $text);
    my ($html, $meta, $errors) = Text::Nimble::render(html => $ast);
    if ($errors) {
        print "[RND ] Errors: '$errors'\n";
    }

    print "[READ] Writing output to '$outfile'...\n";
    open(my $out, ">", $outfile)
        or die "[ERR ] Can't open '$outfile': $!";

    print $out $pre;
    print $out $html;
    print $out $end;
}

sub build_nav_link {
    my $file = shift(@_);
    my $root = shift(@_);
    print "[NAV ] File $file\n";
    my $title = build_title($file);
    $file =~ s/$root//;
    $file =~ s/\.nb$/.html/;
    return "<li><a href=\"$file\">$title</a></li>\n";
}

sub build_nav_dir {
    my $parent = shift(@_);
    my $root   = shift(@_);
    print "[NAV ] Dir '$parent'\n";

    my $nav = "";
    my $title  = build_title($parent);
    opendir(my $dh, $parent);
    while (readdir $dh) {
        my $file = "$parent/$_";

        next if $_ eq ".";
        next if $_ eq "..";
        if ($_ eq ".title") {
            open(my $fh, "<", $file)
                or die "[ERR ] Can't open '$file': $!";
            $title = <$fh>;
        }
        if (-f $file) {
            next unless $file =~ /\.nb$/;
            $nav .= build_nav_link($file, $root);
        }
        if (-d $file) {
            $nav .= build_nav_dir($file, $root);
        }
    }
    if ($nav eq "") {
        return "";
    }
    $parent =~ s/.*\///;
    return "<li><p>$title</p><ul>\n$nav</ul></li>\n";
}

sub build_nav {
    my $root = shift(@_);
    print "[NAV ] Building Navigation from root '$root'\n";
    my $elements = build_nav_dir($root, $root);
    return "<nav><ul>$elements</ul></nav>\n";
}

sub build_title {
    my $path = shift(@_);

    if (-f $path) {
        open(my $fh, "<", $path)
            or die"[ERR ] Can't open '$path': $!";
        foreach my $line (<$fh>) {
            if ($line =~ m/^(\{|!1) .*$/) {
                my $title = $line =~ s/^(\{|!1) //r;
                return $title;
            }
        }
    }
    $path =~ s/^.*\///;
    $path =~ s/[-]/ /g;
    return $path;
}

# Parse command line arguments

my $reqargs = "f:o:";
my $optargs = "chm:s:";
my %options = ();
getopts("$reqargs$optargs", \%options);

if ($options{h}) {
    print_help();
    exit(0);
}

# Make sure all the required arguments are given
$reqargs =~ s/://g;
foreach my $arg (split(//, $reqargs)) {
    if (!$options{$arg}) {
        print "[ERR ] Required option '$arg' not set!\n";
        exit(1);
    }
}

my $indir  = File::Spec->rel2abs($options{f});
my $outdir = File::Spec->rel2abs($options{o});

# Optional arguments
my $macros;
if ($options{m}) {
    open(my $fh, "<", File::Spec->rel2abs($options{m}))
        or die "[ERR ] Can't open '$options{m}': $!";
    local $/ = undef;
    $macros  = <$fh>;
    $macros .= "\n";
} else {
    $macros = "";
}

my $styles;
if ($options{s}) {
    open(my $fh, "<", File::Spec->rel2abs($options{s}))
        or die "[ERR ] Can't open '$options{s}': $!";
    local $/ = undef;
    $styles  = <$fh>;
    $styles .= "\n";
} else {
    $styles = "";
}

if ($options{c}) {
    print "[REM ] Cleaning directory '$outdir'...\n";
    File::Path->remove_tree($outdir);
}

my @infiles = File::Find::Rule->file()
                              ->name('*.nb')
                              ->in($indir);

# Build nav
my $nav = build_nav($indir);

# Build pages
foreach my $in (@infiles) {
    my $out = $in =~ s/$indir/$outdir/r;
    $out =~ s/\.nb$/\.html/;
    my ($drive, $dir, $file) = File::Spec->splitpath($out);

    File::Path->make_path($dir);
    render_html($in, $out, $nav, $styles, $macros);
}

print "[INFO] Finished rendering...\n";
