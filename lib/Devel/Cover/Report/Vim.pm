# Copyright 2012, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Report::Vim;

use strict;
use warnings;

# VERSION
our $LVERSION = do { eval '$VERSION' || "0.001" };  # for development purposes

use Devel::Cover::DB;

use Getopt::Long;
use Template 2.00;

sub get_options
{
    my ($self, $opt) = @_;
    $opt->{outputfile} = "coverage.vim";
    die "Invalid command line options" unless
        GetOptions($opt,
                   qw(
                       outputfile=s
                     ));
}

sub coverage
{
    my ($db, $file, $options) = @_;

    my $statements = $db->cover->file($file)->statement or return ([], []);

    my ($cov, $err) = ([], []);

    for my $location ($statements->items)
    {
        my $l = $statements->location($location);
        my ($c, $e);
        for my $statement (@$l)
        {
            $c ||= $statement->covered;
            $e ||= $statement->error;
        }
        push @$cov, $location if $c;
        push @$err, $location if $e;
    }

    ($cov, $err)
}

sub report
{
    my ($pkg, $db, $options) = @_;

    my $template = Template->new
    ({
        LOAD_TEMPLATES =>
        [
            Devel::Cover::Report::Vim::Template::Provider->new({}),
        ],
    });

    my $vars =
    {
        runs =>
        [
            map
            {
                run    =>               $_->{run},
                perl   =>               $_->{perl},
                OS     =>               $_->{OS},
                start  => scalar gmtime $_->{start},
                finish => scalar gmtime $_->{finish},
            },
            sort {$a->{start} <=> $b->{start}}
            $db->runs
        ],
        now      => time,
        version  => $LVERSION,
        coverage => join ", ", map {
                                       my ($cov, $err) = coverage($db, $_);
                                       local $" = ", ";
                                       my $c = "'$_': [ [ @$cov ], [ @$err ] ]";
                                       my @c = ($c);
                                       $c =~ s/^'blib\//'/;
                                       push @c, $c if $c ne $c[0];
                                       @c
                                   } @{$options->{file}},
    };

    my $out = "$options->{outputdir}/$options->{outputfile}";
    $template->process("vim", $vars, $out) or die $template->error();

    print "Vim script written to $out\n" unless $options->{silent};
}

1;

package Devel::Cover::Report::Vim::Template::Provider;

use strict;
use warnings;

# VERSION

use base "Template::Provider";

my %Templates;

sub fetch
{
    my $self = shift;
    my ($name) = @_;
    # print "Looking for <$name>\n";
    $self->SUPER::fetch(exists $Templates{$name} ? \$Templates{$name} : $name)
}

$Templates{vim} = <<'EOT';
" This file was generated by Devel::Cover Version [% version %]
" Devel::Cover is copyright 2001-2011, Paul Johnson (pjcj@cpan.org)
" Devel::Cover is free. It is licensed under the same terms as Perl itself.
" The latest version of Devel::Cover should be available from my homepage:
" http://www.pjcj.net

[% FOREACH r = runs %]
" Run:          [% r.run    %]
" Perl version: [% r.perl   %]
" OS:           [% r.OS     %]
" Start:        [% r.start  %]
" Finish:       [% r.finish %]

[% END %]

hi HitSign  ctermfg=Green cterm=bold gui=bold guifg=Green
hi MissSign ctermfg=Red   cterm=bold gui=bold guifg=Red

sign define hit  linehl=HitLine  texthl=HitSign  text=>>
sign define miss linehl=MissLine texthl=MissSign text=**

" The signs definitions can be overridden.  To do this add a file called
" devel-cover.vim at some appropriate point in your ~/.vim directory and add
" your local configuration commands there.
" For example, I use the vim solarized theme and I have the following comamnds
" in my local configuration file ~/.vim/local/devel-cover.vim:
"
"    highlight SignColumn ctermbg=0             guibg=#073642
"
"    highlight HitSign    ctermfg=6  cterm=bold guifg=#859900 guibg=#073642 gui=NONE
"    highlight MissSign   ctermfg=1  cterm=bold guifg=#dc322f guibg=#073642 gui=NONE
"
"    " highlight HitLine    ctermbg=8             guibg=#002b36
"    " highlight MissLine   ctermbg=0             guibg=#073642
"

let s:config = findfile("devel-cover.vim", expand('$HOME/.vim') . "/**")
if strlen(s:config)
    echom "Reading local config from " . s:config
    exe "source " . s:config
endif

let s:coverage = { [% coverage %] }

let s:generatedTime = [% now %]

function! BestCoverage(coverageForName)
    let matchBadness = strlen(a:coverageForName)
    for filename in keys(s:coverage)
        let matchQuality = match(a:coverageForName, filename . "$")
        if (matchQuality >= 0 && matchQuality < matchBadness)
            let found = filename
        endif
    endfor

    if exists("found")
        return s:coverage[found]
    else
        echom "No coverage recorded for " . a:coverageForName
        return [[],[]]
    endif
endfunction

let s:signs = {}
let s:signIndex = 1

function! s:CoverageSigns(filename)
    let [hits,misses] = BestCoverage(a:filename)

    if (getftime(a:filename) > s:generatedTime)
        echom "File is newer than coverage report which was generated at " . strftime("%c", s:generatedTime)
    endif

    if (! exists("s:signs['".a:filename."']"))
        let s:signs[a:filename] = []
    endif

    for hit in hits
        let id = s:signIndex
        let s:signIndex += 1
        let s:signs[a:filename] += [id]
        exe ":sign place " . id . " line=" . hit . " name=hit  file=" . a:filename
    endfor

    for miss in misses
        let id = s:signIndex
        let s:signIndex += 1
        let s:signs[a:filename] += [id]
        exe ":sign place " . id . " line=" . miss . " name=miss file=" . a:filename
    endfor
endfunction

function! s:ClearCoverageSigns(filename)
    if(exists("s:signs['". a:filename."']"))
        for signId in s:signs[a:filename]
          exe ":sign unplace " . signId
        endfor
        let s:signs[a:filename] = []
    endif
endfunction

let s:filename = expand("<sfile>")
function! s:AutocommandUncov(sourced)
    if(a:sourced == s:filename)
        call s:ClearCoverageSigns(expand("%:p"))
    endif
endfunction

command! -nargs=0 Cov call s:CoverageSigns(expand("%:p"))
command! -nargs=0 Uncov call s:ClearCoverageSigns(expand("%:p"))

augroup devel-cover
    au!
    exe "au SourcePre " . expand("<sfile>:t") . " call s:AutocommandUncov(expand('<afile>:p'))"

    " show signs automatically for all known files
    for s:filename in keys(s:coverage)
        exe "au BufReadPost " . s:filename . ' call s:CoverageSigns(expand("%:p"))'
    endfor
augroup end

Cov
EOT

1

__END__

=head1 NAME

Devel::Cover::Report::Vim - Backend for displaying coverage data in Vim

=head1 SYNOPSIS

 cover -report vim

=head1 DESCRIPTION

This module provides a reporting mechanism for displaying coverage data in
Vim.  It is designed to be called from the C<cover> program.

By default, the output of this report is a file named C<coverage.vim> in the directory of the coverage database.  To use it, run

 :so cover_db/coverage.vim

and you should see signs in the left column indicating the coverage status of
that line.

coverage.vim adds two user commands: :Cov and :Uncov which can be used to
toggle the state of coverage signs.

The idea and the vim template is shamelessly stolen from Simplecov-Vim.  See
https://github.com/nyarly/Simplecov-Vim

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2012, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

The template is copied from Simplecov-Vim
(https://github.com/nyarly/Simplecov-Vim) and is under the MIT Licence.


The MIT License

Copyright (c) 2011 Judson Lester

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

=cut
