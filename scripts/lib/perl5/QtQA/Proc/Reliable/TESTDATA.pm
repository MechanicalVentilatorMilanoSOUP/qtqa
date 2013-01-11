#############################################################################
##
## Copyright (C) 2013 Digia Plc and/or its subsidiary(-ies).
## Contact: http://www.qt-project.org/legal
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:LGPL$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and Digia.  For licensing terms and
## conditions see http://qt.digia.com/licensing.  For further information
## use the contact form at http://qt.digia.com/contact-us.
##
## GNU Lesser General Public License Usage
## Alternatively, this file may be used under the terms of the GNU Lesser
## General Public License version 2.1 as published by the Free Software
## Foundation and appearing in the file LICENSE.LGPL included in the
## packaging of this file.  Please review the following information to
## ensure the GNU Lesser General Public License version 2.1 requirements
## will be met: http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
##
## In addition, as a special exception, Digia gives you certain additional
## rights.  These rights are described in the Digia Qt LGPL Exception
## version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU
## General Public License version 3.0 as published by the Free Software
## Foundation and appearing in the file LICENSE.GPL included in the
## packaging of this file.  Please review the following information to
## ensure the GNU General Public License version 3.0 requirements will be
## met: http://www.gnu.org/copyleft/gpl.html.
##
##
## $QT_END_LICENSE$
##
#############################################################################

package QtQA::Proc::Reliable::TESTDATA;
use strict;
use warnings;

=head1 NAME

QtQA::Proc::Reliable::TESTDATA - testdata for system tests of QtQA::Proc::Reliable

=head1 DESCRIPTION

This module is not intended for use by the end-user of QtQA::Proc::Reliable.
It is merely a holding area for a suite of testdata to be used in a few autotests
relating to QtQA::Proc::Reliable.

=cut

use Tie::IxHash;
use Readonly;

use base 'Exporter';
our @EXPORT_OK = qw( %TESTDATA );

# Helper regex portions for below testdata
Readonly my %RE => (

    # Matches the text which states we're about to retry a command (not including the reason)
    retry => qr{ \QQtQA::TestScript: It will be retried because\E }xms,

    # Matches the reason why a command was restarted.
    # These are set by the specific QtQA::Proc::Reliable strategies and are cumbersome
    # to test, so we simply allow for any properly formatted text.
    retry_reason => qr{
        (?:
            [^\n]                   # reason fits on a single line ...
            |                       #
            \nQtQA::TestScript:     # ... or it takes multiple lines, all of them prefixed
        )*
    }xms,

    # Matches the prefix on the line where the attempted command is printed
    command => qr{
        \QQtQA::TestScript:     \E\$command
    }xms,

    # Matches the prefix for "the (n'th) attempt at running this command ..."
    # Usage example: $RE{ attempt }{ second }
    attempt => {
        map {
            $_ => qr{ \QQtQA::TestScript: The $_ attempt at running this command:\E }xms
        }
        qw(
            first
            second
            third
            fourth
            fifth
            sixth
        ) # add any more as needed
    },

    # Matches the text generated by failing with an exit code
    # Usage example: $RE{ failed_with_exitcode }{ 12 }
    failed_with_exitcode => {
        map {
            $_ => qr{ \QQtQA::TestScript: ... failed with exit code $_.\E }xms
        }
        (1..255)
    },

);


# This is tied to retain order, as we want the tests to be run in order from least
# to most complex.
#
# Note, can't be Readonly without causing Params::Validate to segfault :(
tie our %TESTDATA => 'Tie::IxHash',

    # simple passing command to ensure correct operation in the normal case
    'git control' => {
        command             => [ 'git', 'clone', 'git://example.com/repo.git' ],
        mock_command        => {
            sequence        => [
                { exitcode => 0, stdout => "Hi\n" },
            ],
        },
        expected_raw_stdout => "Hi\n",
    },

    # recoverable git problem
    'git remote end hung up' => {
        command             => [ 'git', 'clone', 'git://example.com/repo.git' ],
        mock_command        => {
            sequence        => [
                { exitcode => 12, stderr => "fatal: The remote end hung up unexpectedly\n" },
                { exitcode => 12, stderr => "fatal: The remote end hung up unexpectedly\n" },
                { exitcode => 0 },
            ],
        },
        expected_retries    => 2,
        expected_exe_stderr => qr"

            \A

            \Qfatal: The remote end hung up unexpectedly\E                                      \n
            $RE{ attempt }{ first }                                                             \n
            $RE{ command } \Q = ['git','clone','git://example.com/repo.git'];\E                 \n
            $RE{ failed_with_exitcode }{ 12 }                                                   \n
            $RE{ retry } $RE{ retry_reason }                                                    \n

            \Qfatal: The remote end hung up unexpectedly\E                                      \n
            $RE{ attempt }{ second }                                                            \n
            $RE{ command } \Q = ['git','clone','git://example.com/repo.git'];\E                 \n
            $RE{ failed_with_exitcode }{ 12 }                                                   \n
            $RE{ retry } $RE{ retry_reason }                                                    \n

            \z

        "xms,
        expected_raw_stderr => "fatal: The remote end hung up unexpectedly\n" x 2,
    },

    # error message but 0 exit code; make sure we don't retry
    'git remote end hung up with 0 exit code' => {
        command             => [ 'git', 'clone', 'git://example.com/repo.git' ],
        mock_command        => {
            sequence        => [
                { exitcode => 0, stderr => "fatal: The remote end hung up unexpectedly\n" },
            ],
        },
        expected_retries    => 0,
        expected_raw_stderr => "fatal: The remote end hung up unexpectedly\n",
        expected_exe_stderr => "fatal: The remote end hung up unexpectedly\n",
    },

    # unrecoverable git problem with no retries
    'git unrecoverable simple' => {
        command             => [ 'git', 'clone', 'git://example.com/repo.git' ],
        mock_command        => {
            sequence        => [
                { exitcode => 12, stdout => "Cloning...\n", stderr => "fatal: Foo bar the baz\n" },
            ],
        },
        expected_raw_stderr => "fatal: Foo bar the baz\n",
        expected_raw_stdout => "Cloning...\n",
        expected_status     => (12 << 8),
    },

    # unrecoverable git problem with some retries
    'git unrecoverable with retry' => {
        command             => [ 'git', 'clone', 'git://example.com/repo.git' ],
        mock_command        => {
            sequence        => [
                { exitcode => 1,  stderr => "fatal: The remote end hung up unexpectedly\n" },
                { exitcode => 2,  stderr => "fatal: The remote end hung up unexpectedly\n" },
                { exitcode => 58, stderr => "fatal: Foo bar the baz\n" },
            ],
        },
        expected_retries    => 2,
        expected_exe_stderr => qr"

            \A

            \Qfatal: The remote end hung up unexpectedly\E                                      \n
            $RE{ attempt }{ first }                                                             \n
            $RE{ command } \Q = ['git','clone','git://example.com/repo.git'];\E                 \n
            $RE{ failed_with_exitcode }{ 1 }                                                    \n
            $RE{ retry } $RE{ retry_reason }                                                    \n

            \Qfatal: The remote end hung up unexpectedly\E                                      \n
            $RE{ attempt }{ second }                                                            \n
            $RE{ command } \Q = ['git','clone','git://example.com/repo.git'];\E                 \n
            $RE{ failed_with_exitcode }{ 2 }                                                    \n
            $RE{ retry } $RE{ retry_reason }                                                    \n

            \Qfatal: Foo bar the baz\E                                                          \n

            \z

        "xms,
        expected_raw_stderr => ("fatal: The remote end hung up unexpectedly\n" x 2)
                               ."fatal: Foo bar the baz\n",
        expected_status     => (58 << 8),
    },

    # git DNS failure - git:// protocol
    'git DNS failure git://' => {
        command             => [ 'git', 'clone', 'git://example.com/repo.git' ],
        mock_command        => {
            sequence        => [
                { exitcode => 128, stderr => "fatal: Unable to look up example.com (port 9418) (Name or service not known)\n" },
                { exitcode => 0 },
            ],
        },
        expected_retries    => 1,
        expected_exe_stderr => qr"

            \A

            \Qfatal: Unable to look up example.com (port 9418) (Name or service not known)\E    \n
            $RE{ attempt }{ first }                                                             \n
            $RE{ command } \Q = ['git','clone','git://example.com/repo.git'];\E                 \n
            $RE{ failed_with_exitcode }{ 128 }                                                  \n
            $RE{ retry } $RE{ retry_reason }                                                    \n

            \z

        "xms,
        expected_raw_stderr => "fatal: Unable to look up example.com (port 9418) (Name or service not known)\n",
    },

    # git DNS failure - ssh:// protocol
    # This test basically confirms that the Git strategy is subclassing the ssh strategy as
    # expected.  Other ssh:// protocol git issues aren't tested further.
    'git DNS failure ssh://' => {
        command             => [ 'git', 'clone', 'ssh://example.com/repo.git' ],
        mock_command        => {
            sequence        => [
                { exitcode => 128, stderr => "ssh: Could not resolve hostname example.com: Name or service not known\n" },
                { exitcode => 0 },
            ],
        },
        expected_retries    => 1,
        expected_exe_stderr => qr"

            \A

            \Qssh: Could not resolve hostname example.com: Name or service not known\E          \n
            $RE{ attempt }{ first }                                                             \n
            $RE{ command } \Q = ['git','clone','ssh://example.com/repo.git'];\E                 \n
            $RE{ failed_with_exitcode }{ 128 }                                                  \n
            $RE{ retry } $RE{ retry_reason }                                                    \n

            \z

        "xms,
        expected_raw_stderr => "ssh: Could not resolve hostname example.com: Name or service not known\n",
    },


    # various scp problems
    'scp network issues ultimately fatal' => {
        command             => [ 'scp', 'example.com:~/file1', '.' ],
        mock_command        => {
            sequence        => [
                { exitcode => 1, stderr => "ssh: Could not resolve hostname example.com: Name or service not known\n" },
                { exitcode => 2, stderr => "ssh: connect to host example.com: No route to host\n" },
                { exitcode => 3, stderr => "ssh: Connect to host example.com: Network is unreachable\n" },
                { exitcode => 4, stderr => "ssh: connect to host example.com port 1234: Connection timed out\n" },
                { exitcode => 5, stderr => "ssh: connect to host example.com port 22: Connection refused\n" },

                # check that stdout does _not_ cause the command to be retried
                { exitcode => 6, stdout => "ssh: connect to host example.com port 23: Connection refused\n" },
            ],
        },
        expected_retries    => 5,
        expected_exe_stderr => qr"

            \A

            \Qssh: Could not resolve hostname example.com: Name or service not known\E          \n
            $RE{ attempt }{ first }                                                             \n
            $RE{ command } \Q = ['scp','example.com:~/file1','.'];\E                            \n
            $RE{ failed_with_exitcode }{ 1 }                                                    \n
            $RE{ retry } $RE{ retry_reason }                                                    \n

            \Qssh: connect to host example.com: No route to host\E                              \n
            $RE{ attempt }{ second }                                                            \n
            $RE{ command } \Q = ['scp','example.com:~/file1','.'];\E                            \n
            $RE{ failed_with_exitcode }{ 2 }                                                    \n
            $RE{ retry } $RE{ retry_reason }                                                    \n

            \Qssh: Connect to host example.com: Network is unreachable\E                        \n
            $RE{ attempt }{ third }                                                             \n
            $RE{ command } \Q = ['scp','example.com:~/file1','.'];\E                            \n
            $RE{ failed_with_exitcode }{ 3 }                                                    \n
            $RE{ retry } $RE{ retry_reason }                                                    \n

            \Qssh: connect to host example.com port 1234: Connection timed out\E                \n
            $RE{ attempt }{ fourth }                                                            \n
            $RE{ command } \Q = ['scp','example.com:~/file1','.'];\E                            \n
            $RE{ failed_with_exitcode }{ 4 }                                                    \n
            $RE{ retry } $RE{ retry_reason }                                                    \n

            \Qssh: connect to host example.com port 22: Connection refused\E                    \n
            $RE{ attempt }{ fifth }                                                             \n
            $RE{ command } \Q = ['scp','example.com:~/file1','.'];\E                            \n
            $RE{ failed_with_exitcode }{ 5 }                                                    \n
            $RE{ retry } $RE{ retry_reason }                                                    \n

            \z

        "xms,
        expected_raw_stderr =>
            "ssh: Could not resolve hostname example.com: Name or service not known\n"
           ."ssh: connect to host example.com: No route to host\n"
           ."ssh: Connect to host example.com: Network is unreachable\n"
           ."ssh: connect to host example.com port 1234: Connection timed out\n"
           ."ssh: connect to host example.com port 22: Connection refused\n"
        ,
        expected_raw_stdout => "ssh: connect to host example.com port 23: Connection refused\n",
        expected_status     => (6 << 8),
    },


    # simple check with explicitly loading a strategy
    'non-auto ssh failure' => {
        command             => [ 'frobnitz' ],
        reliable            => [ 'ssh' ],
        mock_command        => {
            sequence        => [
                # check that the requested `reliable' loaded ssh strategy ...
                { exitcode => 128, stderr => "ssh: Could not resolve hostname example.com: Name or service not known\n" },
                # ...and did _not_ load `git' strategy
                { exitcode => 128, stderr => "fatal: Unable to look up example.com (port 9418) (Name or service not known)\n" },
            ],
        },
        expected_retries    => 1,
        expected_exe_stderr => qr"

            \A

            \Qssh: Could not resolve hostname example.com: Name or service not known\E          \n
            $RE{ attempt }{ first }                                                             \n
            $RE{ command } \Q = ['frobnitz'];\E                                                 \n
            $RE{ failed_with_exitcode }{ 128 }                                                  \n
            $RE{ retry } $RE{ retry_reason }                                                    \n

            \Qfatal: Unable to look up example.com (port 9418) (Name or service not known)\E    \n

            \z

        "xms,
        expected_raw_stderr =>
            "ssh: Could not resolve hostname example.com: Name or service not known\n"
           ."fatal: Unable to look up example.com (port 9418) (Name or service not known)\n"
        ,
        expected_status     => (128 << 8),
    },

;

1;
