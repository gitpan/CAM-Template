package CAM::Template;

=head1 NAME

CAM::Template - Clotho-style search/replace HTML templates

=head1 SYNOPSIS

  use CAM::Template;
  my $tmpl = new CAM::Template($tmpldir . "/main_tmpl.html");
  $tmpl->addParams(url => "http://foo.com/",
                   date => localtime(),
                   name => "Carol");
  $tmpl->addParams(\%more_params);
  $tmpl->setLoop("birthdaylist", name => "Eileen", date => "Sep 12");
  $tmpl->addLoop("birthdaylist", name => "Chris",  date => "Oct 13");
  $tmpl->addLoop("birthdaylist", [{name => "Dan",   date => "Feb 12"},
                                  {name => "Scott", date => "Sep 24"}]);
  print "Content-Type: text/html\n\n";
  $tmpl->print();

=head1 DESCRIPTION

This package is intended to replace Clotho's traditional ::PARAM::
syntax with an object-oriented API.  This syntax is overrideable by
subclasses.

=cut

require 5.005_62;
use strict;
use warnings;
use Carp;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use CAM::Template ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);
our $VERSION = '0.74';

## Global package settings

my $global_include_files = 1;

# Flags for the in-memory cache
my $global_use_cache = 1;
my %cache = ();
my %cache_times = ();

#==============================

=head1 FUNCTIONS 

=over 4

=cut

#==============================

=item patterns

This class method returns a series of regular expressions used for
template searching and replacing.  Modules which subclass
CAM::Template can override this method to implement a different
template syntax.

=cut

sub patterns
{
   my $pkg = shift;

   return {
      # $1 is the loop name, $2 is the loop body
      loop => qr/<cam_loop\s+name\s*=\s*\"?([\w\-]+)\"?>(.*?)<\/cam_loop>/is,

      # a string that looks like one of the "vars" below for
      # substituting the loop variable.  This will be used in:
      #    $template =~ s/loop-pattern/loop_out-pattern/;
      loop_out => '::$1::',

      # $1 is the variable name, $2 is the conditional body
      if => qr/\?\?([\w\-]+?)\?\?(.*?)\?\?\1\?\?/s,
      unless => qr/\?\?!([\w\-]+?)\?\?(.*?)\?\?!\1\?\?/s,

      # $1 is the variable name
      vars => [
               qr/<!--\s*::([\w\-]+?)::\s*-->/s,
               qr/::([\w\-]+?)::/s,
               qr/;;([\w\-]+?);;/s,
               ],
          
      # $1 is the variable name, $2 is the value to set it to
      staticvars => qr/::([\w\-]+)==(.{0,80}?)::/,
   };
}

#==============================


#==============================

=item new

=item new FILENAME

=item new FILENAME, PARAMS

Create a new template object.  You can specify the template filename and
the replacement dictionary right away, or do it later via methods.

=cut

#==============================
sub new
{
   my $pkg = shift;

   my $self = bless({
      filename => "",
      params => {},
      string => "",
      loops => {},
      use_cache => $global_use_cache,
      include_files => $global_include_files,
      patterns => $pkg->patterns(),
   }, $pkg);

   if (@_ > 0 && !$self->setFilename(shift))
   {
      return undef;
   }
   if (@_ > 0 && !$self->addParams(@_))
   {
      return undef;
   }

   return $self;
}


#==============================

=item setFileCache 0|1

Indicate whether the template file should be cached in memory.
Defaults to 1 (aka true).  This can be used either on an object or
globally:

    my $tmpl = new CAM::Template();
    $tmpl->setFileCache(0);

    CAM::Template->setFileCache(0);

The global value only affects future template objects, not existing
ones.

=cut

#==============================
sub setFileCache
{
   my $self = shift;
   my $bool = shift;

   if (ref($self))
   {
      $self->{use_cache} = $bool;
      return $self;
   }
   else
   {
      $global_use_cache = $bool;
      return 1;
   }
}

#==============================

=item setIncludeFiles 0|1

Indicate whether the template file should be able to include other template files automatically via the

   <!-- #include template="<filename>" -->

directive.  Defaults to 1 (aka true).  Note that this is recursive, so
don't have a file include itself!  This method can be used either on
an object or globally:

    my $tmpl = new CAM::Template();
    $tmpl->setIncludeFiles(0);

    CAM::Template->setIncludeFiles(0);

The global value only affects future template objects, not existing
ones.

=cut

#==============================
sub setIncludeFiles
{
   my $self = shift;
   my $bool = shift;

   if (ref($self))
   {
      $self->{include_files} = $bool;
      return $self;
   }
   else
   {
      $global_include_files = $bool;
      return 1;
   }
}

#==============================

=item setFilename FILENAME

Specify the template file to be used.  Returns false if the file does
not exist or the object if it does.  This loads and preparses the file.

=cut

#==============================
sub setFilename
{
   my $self = shift;
   my $filename = shift;

   # Validate input
   if ((! $filename) || (! -r $filename))
   {
      &carp("File '$filename' cannot be read");
      return undef;
   }
   $self->{filename} = $filename;
   $self->{string} = $self->_fetchfile($filename);
   $self->_preparse();
   return $self;
}

#==============================

=item setString STRING

Specify template content to be used.  Use this instead of setFilename if
you already have the contents in memory.  This preparses the string.

=cut

#==============================
sub setString
{
   my $self = shift;
   $self->{string} = shift;
   $self->{filename} = "";
   $self->_preparse();
   return $self;
}

#==============================

=item addLoop LOOPNAME, HASHREF | KEY => VALUE, ...

=item addLoop LOOPNAME, ARRAYREF

Add to an iterating portion of the page.  This extracts the <cam_loop>
from the template, fills it with the specified parameters (and any
previously specified with setParams() or addParams()), and appends to
the LOOPNAME parameter in the params list.

If the ARRAYREF form of the method is used, it behaves as if you had done:

    foreach my $row (@$ARRAYREF) {
       $tmpl->addLoop($LOOPNAME, $row);
    }

so, the elements of the ARRAYREF are hashrefs representing a series of
rows to be added.

=cut

#==============================
sub addLoop
{
   my $self = shift;
   my $loopname = shift;
   # additional params are collected below

   return undef if (!exists $self->{loops}->{$loopname});

   while (@_ > 0 && $_[0] && ref($_[0]) && ref($_[0]) eq "ARRAY")
   {
      my $looparray = shift;
      foreach my $loop (@$looparray)
      {
         if (!$self->addLoop($loopname, $loop))
         {
            return undef;
         }
      }
      # If we run out of arrayrefs, quit
      if (@_ == 0)
      {
         return $self;
      }
   }

   my $pkg = ref($self);
   my $looptemplate = $pkg->new();
   $looptemplate->setString($self->{loops}->{$loopname});
   $looptemplate->setParams(%{$self->{params}}, $loopname => "", @_);
   $self->{params}->{$loopname} = "" if (!exists $self->{params}->{$loopname});
   $self->{params}->{$loopname} .= $looptemplate->toString();
   return $self;
}

#==============================

=item setLoop LOOPNAME, HASHREF | KEY => VALUE, ...

Exactly like addLoop above, except it clears the loop first.  This is
useful for nested loops.

=cut

#==============================
sub setLoop
{
   my $self = shift;
   my $loopname = shift;

   $self->{params}->{$loopname} = "";
   return $self->addLoop($loopname, @_);
}
#==============================

=item addParams [HASHREF | KEY => VALUE], ...

Specify the search/replace dictionary for the template.  The arguments
can either be key value pairs, or hash references (it is permitted to
mix the two as of v0.71 of this library).  For example:

    my %hash = (name => "chris", age => 30);
    $tmpl1->addParams(%hash);

    my $hashref = \%hash;
    $tmpl2->addParams($hashref);

Returns false if the hash has an uneven number of arguments, or the
argument is not a hash reference.  Returns the object otherwise.

Note: this I<appends> to the parameter list.  To replace the list, use
the setParams method instead.

=cut

#==============================
sub addParams
{
   my $self = shift;
   # additional arguments processed below


   # store everything up in a temp hash so we can detect errors and
   # quit before applying these params to the object.
   my %params = ();

   while (@_ > 0)
   {
      if (!defined $_[0])
      {
         &carp("Undefined key in the parameter list");
         return undef;
      }
      elsif (ref($_[0]))
      {
         my $ref = shift;
         if (ref($ref) ne "HASH")
         {
            &carp("Parameter list has a reference that is not a hash reference");
            return undef;
         }
         %params = (%params, %$ref);
      }
      elsif (@_ == 1)
      {
         &carp("Uneven number of arguments in key/value pair list");
         return undef;
      }
      else
      {
         # get a key value pair
         my $key = shift;
         $params{$key} = shift;
      }
   }

   foreach my $key (keys %params)
   {
      $self->{params}->{$key} = $params{$key};
   }
   return $self;
}

#==============================

=item setParams HASHREF | KEY => VALUE, ...

Exactly like addParams above, except it clears the parameter list first.

=cut

#==============================
sub setParams
{
   my $self = shift;
   
   $self->{params} = {};
   return $self->addParams(@_);
}


#==============================
# PRIVATE FUNCTION
sub _preparse
{
   my $self = shift;

   $self->{loops} = {};
   my $re = $self->{patterns}->{loop};
   my ($start,$end) = split /\$1/, $self->{patterns}->{loop_out}, 2;
   while ($self->{string} =~ s/$re/$start$1$end/)
   {
      $self->{loops}->{$1} = $2;
   }
   return $self;
}


#==============================
# PRIVATE FUNCTION
sub _fetchfile
{
   my $self = shift;
   my $filename = shift;

   if ($self->{use_cache} && exists $cache{$filename} &&
       $cache_times{$filename} >= (stat($filename))[9])
   {
      return $cache{$filename};
   }
   else
   {
      local *FILE;
      if (!open(FILE, $filename))
      {
         &carp("Failed to open file '$filename': $!");
         return undef;
      }
      local $/ = undef;
      my $content = <FILE>;
      close(FILE);

      if ($self->{include_files})
      {
         # Recursively add included files -- must be in the same directory
         my $dir = $filename;
         $dir =~ s,/[^/]+$,,;  # remove filename
         $dir .= "/" if ($dir =~ /[^\/]$/);
         $content =~ s|<!\-\-\s*\#include\s+template=\"([^\"]+)\"\s*\-\->|  $self->_fetchfile("$dir$1")  |ge;
      }

      if ($self->{use_cache})
      {
         $cache{$filename} = $content;
         $cache_times{$filename} = (stat($filename))[9];
      }
      return $content;
   }
}

#==============================

=item toString

Executes the search/replace and returns the content.

=cut

#==============================
sub toString
{
   my $self = shift;

   my $content = $self->{string};

   my $re_hash = $self->{patterns};
   {
      my %params = ();

      # Turn off warnings, since it is likely that some parameters
      # will be undefined
      no warnings;

      # Retrieve parameters set in the template files
      $content =~ s/$$re_hash{staticvars}/$params{$1}=$2; ""/ge;

      # incoming params can override template params
      %params = (%params, %{$self->{params}});

      # Do the following multiple times to handle nested conditionals
      my $pos = 1;
      my $neg = 1;
      do {
         if ($neg)
         {
            $neg = ($content =~ s/$$re_hash{unless}/(!$params{$1}) ? $2 : ''/ge);
         }
         if ($pos)
         {
            $pos = ($content =~ s/$$re_hash{if}/$params{$1} ? $2 : ''/ge);
         }
      } while ($neg || $pos);
      foreach my $re (@{$re_hash->{vars}})
      {
         $content =~ s/$re/$params{$1}/g;
      }
   }

   return $content;
}

#==============================

=item print

=item print FILEHANDLE

Sends the replaced content to the currently selected output (usually
STDOUT) or the supplied filehandle.

=cut

#==============================
sub print
{
   my $self = shift;
   my $filehandle = shift;

   my $content = $self->toString();
   return undef if (!defined $content);

   if ($filehandle)
   {
      print $filehandle $content;
   }
   else
   {
      print $content;
   }
   return $self;
}



1;
__END__

=back

=head1 AUTHOR

Chris Dolan, Clotho Advanced Media, I<chris@clotho.com>

=cut
