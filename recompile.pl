#!/usr/bin/env perl
use strict;
use warnings;
use autodie;

use List::Util qw(max any);

##### DEBUG
use constant DEBUG => 0;

# a debug helper that shows a vector as a range
sub vec2range {
  my $vec = shift;

  if ( !defined $vec ) { return '<uninitialized>' }
  my @ranges;

  my ( $a, $b );
  for ( my $i = 0 ; $i < length($vec) * 8 ; $i++ ) {
    if ( vec( $vec, $i, 1 ) ) {

      # bit set - either mark this as the starting point
      if ( !defined $a ) { $a = $i }

      # or advance the endpoint
      else { $b = $i }
    } elsif ( defined $a ) {

      # bit clear
      push @ranges, $a . ( defined $b ? '-' . $b : '' );
      $a = $b = undef;
    }
  }

  if ( defined $a ) {
    push @ranges, $a . ( defined $b ? '-' . $b : '' );
  }
  if (@ranges) { return join( ', ', @ranges ) }
  return '<empty>';
}

# print machine state
my @msg_map;

sub _d {
  if (DEBUG) {
    my $message     = shift;
    my $pc          = shift;
    my $op          = shift;
    my $i           = shift;
    my $timer_delay = shift;
    my @v           = @_;

    # machine state
    for ( my $j = 0 ; $j < 16 ; $j++ ) {
      print " . v[" . $j . "]: " . vec2range( $v[$j] ) . "\n";
    }
    print " . i: " . vec2range($i) . "\n";

    printf("====\n");

    # current instruction and meaning
    printf( "[%03x] %04x %s\n", $pc, $op, $message );

    $msg_map[$pc] = $message;
  }
}

##### BITVECTOR OPERATIONS
# Turn a vector into a list of elements
sub vec2list {
  my @ret;
  for ( my $i = 0 ; $i < length( $_[0] ) * 8 ; $i++ ) {
    push @ret, $i if vec( $_[0], $i, 1 );
  }
  return @ret;
}

# Turn a list of elements into a vector
sub list2vec {
  my $ret;
  vec( $ret, $_, 1 ) = 1 foreach @_;
  return $ret;
}

# "Normalize" a vector by dropping "\0" off the end
sub vecnorm {
  my $ret = shift;
  $ret =~ s/\0+$//;
  return $ret;
}

sub load_rom {
  my ( $ram, $filename ) = @_;

  open my $fp, '<:raw', $filename;
  read $fp, my $string, max( 4096 - 512, -s $fp );
  my @rom = unpack 'C*', $string;
  close $fp;

  # copy rom into ram
  for ( my $i = 0 ; $i < scalar @rom ; $i++ ) {
    $ram->[ $i + 0x200 ]{rom} = $rom[$i];
    vec( $ram->[ $i + 0x200 ]{ram}, $rom[$i], 1 ) = 1;
  }
}

if ( scalar @ARGV == 0 ) {
  print "Usage: $0 <file>.ch8\n";
  exit 0;
}

my @ram;

# Read input file
load_rom( \@ram, $ARGV[0] );

sub iterate {
  my $pc          = shift;
  my $i           = shift;
  my $timer_delay = shift;
  my @v           = @{ +shift };
  my @stack       = @_;

  while (1) {
    if    ( $pc < 0x200 ) { die "PC underflow" }
    elsif ( $pc > 4094 )  { die "PC overflow" }

    # check for exec of uninitialized ram
    if ( !( defined $ram[$pc] && defined $ram[$pc]{rom} ) ) {
      die "Location $pc is uninitialized: runaway PC?";
    } elsif ( !( defined $ram[ $pc + 1 ] && defined $ram[ $pc + 1 ]{rom} ) ) {
      die "Location $pc + 1 is uninitialized: runaway PC?";
    }

    # check for exec of a write area
    #  TODO: technically, this is legal, if they write only the same byte
    if ( $ram[$pc]{write} ) {
      die "Location $pc already marked as Written Data but also executed: self-modifying code?";
    } elsif ( $ram[ $pc + 1 ]{write} ) {
      die "Location $pc + 1 already marked as Written Data but also executed: self-modifying code?";
    }

    # block has Code path, check its ranges and return if fully covered
    my $stack_str = join( '', map { sprintf( '%03x', $_ ) } @stack );
    if ( $ram[$pc]{exec} ) {

      # a check for alignment problems
      if ( $ram[$pc]{exec}{nibble} == 2 ) {
        die "Location $pc already marked as Low Instruction nibble: alignment issue?";
      }

      if ( !$ram[ $pc + 1 ]{exec}{nibble} ) {
        die "Location $pc already marked as Instruction but $pc + 1 not: analyser bug?";
      } elsif ( $ram[ $pc + 1 ]{exec}{nibble} == 1 ) {
        die "Location $pc + 1 already marked as High Instruction nibble: alignment issue?";
      }

      if ( $ram[$pc]{exec}{$stack_str} ) {

        # check if we can Ret from this or more passes needed
        my $t_i = defined $i ? vecnorm($i) : chr(255) x 512;
        my $ret = vecnorm( $t_i & $ram[$pc]{exec}{$stack_str}{i} ) eq $t_i;

        for ( my $j = 0 ; $ret && $j < 16 ; $j++ ) {
          my $t_v = defined $v[$j] ? vecnorm( $v[$j] ) : chr(255) x 32;
          $ret = vecnorm( $t_v & $ram[$pc]{exec}{$stack_str}{v}[$j] ) eq $t_v;
        }
        if ($ret) {
          $ret = ( $timer_delay <= $ram[$pc]{exec}{$stack_str}{timer_delay} );
        }
        if ($ret) {

          # all checks passed: the machine state here has already been examined further
          print "CODE PATH TERMINATED AT PC=" . sprintf( "%03x", $pc ) . "\n" if DEBUG;
          return;
        }

        # bummer, have to parse this further.  grow each value to cover both new and existing cases
        $i = vecnorm( $i | $ram[$pc]{exec}{$stack_str}{i} ) if ( defined $i );
        for my $j ( 0 .. 15 ) {
          $v[$j] = vecnorm( $v[$j] | $ram[$pc]{exec}{$stack_str}{v}[$j] ) if ( defined $v[$j] );
        }
        $timer_delay = max( $timer_delay, $ram[$pc]{exec}{$stack_str}{timer_delay} );
      }
    } else {

      # previously unvisited area
      if ( $ram[ $pc + 1 ]{exec} ) {
        die "Location $pc + 1 already visited: alignment issue?";
      }
    }

    # mark code location on the map
    $ram[$pc]{exec}{nibble}                  = 1;
    $ram[$pc]{exec}{$stack_str}{i}           = defined $i ? $i : chr(255) x 512;
    $ram[$pc]{exec}{$stack_str}{v}[$_]       = defined $v[$_] ? $v[$_] : chr(255) x 32 for ( 0 .. 15 );
    $ram[$pc]{exec}{$stack_str}{timer_delay} = $timer_delay;
    $ram[ $pc + 1 ]{exec}{nibble}            = 2;

    # retrieve opcode
    my $op = ( $ram[$pc]{rom} << 8 ) | $ram[ $pc + 1 ]{rom};

    # helpers to parse an instruction
    my $opA = ( ( $op & 0xF000 ) >> 12 );
    my $opB = ( ( $op & 0x0F00 ) >> 8 );
    my $opC = ( ( $op & 0x00F0 ) >> 4 );
    my $opD = ( $op & 0x000F );

    my $opL = ( $op & 0x00FF );

    my $opADDR = ( $op & 0x0FFF );

    if ( $opA == 0 ) {

      # call machine routine
      if ( $opADDR == 0x0E0 ) {

        # screen clear - affects nothing
        _d( "Screen clear", $pc, $op, $i, $timer_delay, @v );

      } elsif ( $opADDR == 0xEE ) {

        # RET - return the machine state
        _d( "RET from sub", $pc, $op, $i, $timer_delay, @v );
        if ( !@stack ) {
          die "Return from empty stack at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
        }
        $pc = pop @stack;
      } else {
        die "Illegal opcode at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
      }
      $pc += 2;
    } elsif ( $opA == 1 ) {

      # Jump statement
      _d( "JUMP to " . sprintf( "%03x", $opADDR ), $pc, $op, $i, $timer_delay, @v );
      $pc = $opADDR;
    } elsif ( $opA == 2 ) {

      # Call subroutine
      _d( "CALL SUB at " . sprintf( "%03x", $opADDR ), $pc, $op, $i, $timer_delay, @v );

      # Push our address onto the stack and move the PC
      push @stack, $pc;

      $pc = $opADDR;
    } elsif ( $opA == 3 || $opA == 4 ) {

      _d( "TEST " . ( $opA == 3 ? 'IN' : '' ) . "equality v[$opB] vs $opL", $pc, $op, $i, $timer_delay, @v );

      # literal (in)equality test
      if ( !defined $v[$opB] ) {
        warn "Uninitialized register $opB at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
        $v[$opB] = chr(255) x 32;
      }

      my $equal    = vecnorm( $v[$opB] & list2vec($opL) );
      my $nonequal = vecnorm( $v[$opB] ^ $equal );

      my $exec = ( $opA == 3 ? $nonequal : $equal );
      my $skip = ( $opA == 3 ? $equal    : $nonequal );

      print "-> exec_vec = " . vec2range($exec) . ", skip_vec = " . vec2range($skip) . "\n" if DEBUG;

      $pc += 2;

      if ($exec) {

        # condition is possible to be False, no skipping

        if ( !$skip ) {

          # this is a special case where we can ignore the iterate call and just go
          $v[$opB] = $exec;

        } else {

          # set up a call into the instruction
          my @new_v = @v;
          $new_v[$opB] = $exec;
          iterate( $pc, $i, $timer_delay, \@new_v, @stack );

          # ready to proceed.  but first, update our V.

          $v[$opB] = $skip;
          $pc += 2;
        }
      } else {

        # Condition never executed: simply bypass this instruction
        $v[$opB] = $skip;
        $pc += 2;
      }
    } elsif ( $opA == 5 || $opA == 9 ) {
      if ( $opD == 0 ) {

        if ( !defined $v[$opB] ) {
          warn "Uninitialized register $opB at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opB] = chr(255) x 32;
        }

        if ( !defined $v[$opC] ) {
          warn "Uninitialized register $opC at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opC] = chr(255) x 32;
        }

        # the overlap of these two determines equality
        my $equal = vecnorm( $v[$opB] & $v[$opC] );

        $pc += 2;

        # TODO this could be better with a concept of linked registers or unlinked

        if ( $opA == 5 ) {

          _d( "TEST EQUALITY v[$opB] vs $opL\n + equal vec = " . vec2range($equal), $pc, $op, $i, $timer_delay, @v );

          if ($equal) {

            # The two are sometimes equal: iterate on the case where they are not
            iterate( $pc, $i, $timer_delay, \@v, @stack );

            # Continue on the "skipped" path where they are
            $v[$opB] = $v[$opC] = $equal;
          }

          $pc += 2;

        } else {

          # the skipped instruction MAY be executed for the equality cases
          _d( "TEST INEQUALITY v[$opB] vs $opL\n + equal vec = " . vec2range($equal), $pc, $op, $i, $timer_delay, @v );
          if ($equal) {
            my @new_v = @v;
            $new_v[$opB] = $new_v[$opC] = $equal;
            iterate( $pc, $i, $timer_delay, \@new_v, @stack );
          }

          # always execute the NEQ branch
        }
      } else {
        die "Illegal opcode at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
      }

      $pc += 2;
    } elsif ( $opA == 6 ) {

      _d( "SET v[$opB] to $opL", $pc, $op, $i, $timer_delay, @v );

      # Assign literal to register
      $v[$opB] = list2vec($opL);

      $pc += 2;
    } elsif ( $opA == 7 ) {
      _d( "ADD LIT v[$opB] to $opL", $pc, $op, $i, $timer_delay, @v );

      if ( !defined $v[$opB] ) {
        warn "Uninitialized register $opB at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
        $v[$opB] = chr(255) x 32;
      }

      # Add literal to register
      $v[$opB] = list2vec( map { ( $_ + $opL ) % 256 } vec2list( $v[$opB] ) );

      $pc += 2;
    } elsif ( $opA == 8 ) {

      # Register-register operations
      if ( $opD == 0 ) {

        _d( "SET v[$opB] to v[$opC]", $pc, $op, $i, $timer_delay, @v );

        # Assign register to register
        if ( !defined $v[$opC] ) {
          warn "Uninitialized register $opC at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opC] = chr(255) x 32;
        }
        $v[$opB] = $v[$opC];
      } elsif ( $opD == 1 ) {

        # OR operation
        _d( "SET v[$opB] |= v[$opC]", $pc, $op, $i, $timer_delay, @v );
        if ( !defined $v[$opB] ) {
          warn "Uninitialized register $opB at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opB] = chr(255) x 32;
        }
        if ( !defined $v[$opC] ) {
          warn "Uninitialized register $opC at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opC] = chr(255) x 32;
        }

        my @result_set;
        foreach my $c ( vec2list( $v[$opC] ) ) {
          foreach my $b ( vec2list( $v[$opB] ) ) {
            push @result_set, ( $b | $c );
          }
        }
        $v[$opB] = list2vec(@result_set);
        $v[0xF] = list2vec(0);
      } elsif ( $opD == 2 ) {

        # AND operation
        _d( "SET v[$opB] &= v[$opC]", $pc, $op, $i, $timer_delay, @v );
        if ( !defined $v[$opB] ) {
          warn "Uninitialized register $opB at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opB] = chr(255) x 32;
        }
        if ( !defined $v[$opC] ) {
          warn "Uninitialized register $opC at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opC] = chr(255) x 32;
        }
        my @result_set;
        foreach my $c ( vec2list( $v[$opC] ) ) {
          foreach my $b ( vec2list( $v[$opB] ) ) {
            push @result_set, ( $b & $c );
          }
        }
        $v[$opB] = list2vec(@result_set);
        $v[0xF] = list2vec(0);
      } elsif ( $opD == 3 ) {

        _d( "SET v[$opB] ^= v[$opC]", $pc, $op, $i, $timer_delay, @v );

        # XOR operation
        if ( !defined $v[$opB] ) {
          warn "Uninitialized register $opB at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opB] = chr(255) x 32;
        }
        if ( !defined $v[$opC] ) {
          warn "Uninitialized register $opC at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opC] = chr(255) x 32;
        }
        my @result_set;
        foreach my $c ( vec2list( $v[$opC] ) ) {
          foreach my $b ( vec2list( $v[$opB] ) ) {
            push @result_set, ( $b ^ $c );
          }
        }
        $v[$opB] = list2vec(@result_set);
        $v[0xF] = list2vec(0);
      } elsif ( $opD == 4 ) {

        _d( "SET v[$opB] += v[$opC]", $pc, $op, $i, $timer_delay, @v );

        # ADD
        if ( !defined $v[$opB] ) {
          warn "Uninitialized register $opB at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opB] = chr(255) x 32;
        }
        if ( !defined $v[$opC] ) {
          warn "Uninitialized register $opC at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opC] = chr(255) x 32;
        }

        # this is chaotic but it basically makes a new list out of the combination of both registers
        my @result_set;
        foreach my $c ( vec2list( $v[$opC] ) ) {
          foreach my $b ( vec2list( $v[$opB] ) ) {
            push @result_set, ( $b + $c );
          }
        }
        $v[$opB] = list2vec( map { $_ % 256 } @result_set );
        $v[0xF] = list2vec( map { $_ > 255 } @result_set );
      } elsif ( $opD == 5 ) {

        _d( "SET v[$opB] -= v[$opC]", $pc, $op, $i, $timer_delay, @v );

        # SUBTRACT
        if ( !defined $v[$opB] ) {
          warn "Uninitialized register $opB at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opB] = chr(255) x 32;
        }
        if ( !defined $v[$opC] ) {
          warn "Uninitialized register $opC at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opC] = chr(255) x 32;
        }
        my @result_set;
        foreach my $c ( vec2list( $v[$opC] ) ) {
          foreach my $b ( vec2list( $v[$opB] ) ) {
            push @result_set, ( $b - $c );
          }
        }
        $v[$opB] = list2vec( map { ( $_ + 256 ) % 256 } @result_set );
        $v[0xF] = list2vec( map { $_ >= 0 } @result_set );

      } elsif ( $opD == 6 ) {

        _d( "SET v[$opB] = v[$opC] >> 1", $pc, $op, $i, $timer_delay, @v );

        # shift right
        if ( !defined $v[$opC] ) {
          warn "Uninitialized register $opC at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opC] = chr(255) x 32;
        }

        my @listC = vec2list( $v[$opC] );
        $v[$opB] = list2vec( map { $_ >> 1 } @listC );
        $v[0xF] = list2vec( map { $_ & 1 } @listC );
      } elsif ( $opD == 7 ) {

        # other subtract
        # SUBTRACT
        _d( "SET v[$opB] = v[$opC] - b", $pc, $op, $i, $timer_delay, @v );
        if ( !defined $v[$opB] ) {
          warn "Uninitialized register $opB at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opB] = chr(255) x 32;
        }
        if ( !defined $v[$opC] ) {
          warn "Uninitialized register $opC at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opC] = chr(255) x 32;
        }
        my @result_set;
        foreach my $c ( vec2list( $v[$opC] ) ) {
          foreach my $b ( vec2list( $v[$opB] ) ) {
            push @result_set, ( $c - $b );
          }
        }
        $v[$opB] = list2vec( map { ( $_ + 256 ) % 256 } @result_set );
        $v[0xF] = list2vec( map { $_ >= 0 } @result_set );
      } elsif ( $opD == 0xE ) {

        # shift left
        _d( "SET v[$opB] = v[$opC] << 1", $pc, $op, $i, $timer_delay, @v );
        if ( !defined $v[$opC] ) {
          warn "Uninitialized register $opC at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opC] = chr(255) x 32;
        }
        my @listC = vec2list( $v[$opC] );
        $v[$opB] = list2vec( map { $_ << 1 } @listC );
        $v[0xF] = list2vec( map { ( $_ & 0x80 ) >> 7 } @listC );
      } else {
        die "Illegal opcode at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
      }

      $pc += 2;
    } elsif ( $opA == 0xA ) {

      # Set I to (addr)
      _d( "SET I to " . sprintf( "%03x", $opADDR ), $pc, $op, $i, $timer_delay, @v );
      if ( $opADDR < 0x200 ) {
        warn "Program sets I to $opADDR at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
      }
      $i = list2vec($opADDR);
      $pc += 2;
    } elsif ( $opA == 0xB ) {
      die "BXXX";

      # TODO TODO TODO
      $pc = $opADDR + $v[0];
      $pc += 2;
    } elsif ( $opA == 0xC ) {

      _d( "SET v[$opB] to rand() & $opL", $pc, $op, $i, $timer_delay, @v );

      # get rand & NNN
      $v[$opB] = list2vec( map { $_ & $opL } ( 0 .. 255 ) );
      $pc += 2;
    } elsif ( $opA == 0xD ) {

      _d( "PLOT $opD height at v[$opB], v[$opC]", $pc, $op, $i, $timer_delay, @v );
      if ( $opD == 0 ) {
        warn "Zero-height sprite at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
        $v[0xF] = list2vec(0);
      } else {

        # it's plot - this marks data for Read!
        for ( my $j = 0 ; $j < $opD ; $j++ ) {
          foreach my $offset ( vec2list($i) ) {
            $ram[ $offset + $j ]{read} = 1;
          }
        }
        $v[0xF] = list2vec( 0, 1 );
      }
      $pc += 2;
    } elsif ( $opA == 0xE ) {
      if ( $opL == 0x9E || $opL == 0xA1 ) {

        _d( "CHECK KEY STATE v[$opB]", $pc, $op, $i, $timer_delay, @v );

        # check key down or up
        #  note that key check is & with 0xF
        $pc += 2;

        iterate( $pc, $i, $timer_delay, \@v, @stack );
        $pc += 2;
      } else {
        die "Illegal opcode at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
      }
    } elsif ( $opA == 0xF ) {
      if ( $opL == 0x07 ) {

        _d( "GET DELAY INTO v[$opB]", $pc, $op, $i, $timer_delay, @v );

        # get delay timer
        $v[$opB] = list2vec( 0 .. $timer_delay );
      } elsif ( $opL == 0x0A ) {

        # wait key
        _d( "AWAIT KEY INTO v[$opB]", $pc, $op, $i, $timer_delay, @v );
        $v[$opB] = list2vec( 0 .. 15 );
      } elsif ( $opL == 0x15 ) {

        # delay may take any value between 0 and the highest it's ever been
        $timer_delay = max( $timer_delay, vec2list($opB) );
      } elsif ( $opL == 0x18 ) {

        _d( "SET SOUND TIMER", $pc, $op, $i, $timer_delay, @v );

        # set sound timer - does nothing
      } elsif ( $opL == 0x1E ) {

        _d( "ADVANCE I BY V[$opB]", $pc, $op, $i, $timer_delay, @v );

        # advance I by v[opB]
        my @result_set;
        foreach my $j ( vec2list($i) ) {
          foreach my $b ( vec2list( $v[$opB] ) ) {
            if ( $j + $b < 4096 ) {
              push @result_set, ( $j + $b );
            } else {
              warn "I + v[$opB] may exceed 4096 at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
            }
          }
        }
        $i = list2vec(@result_set);
      } elsif ( $opL == 0x29 ) {

        _d( "HEX-DIGIT of v[$opB] to I", $pc, $op, $i, $timer_delay, @v );

        if ( !defined $v[$opB] ) {
          warn "Uninitialized register $opB at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          $v[$opB] = chr(255) x 32;
        }

        # assign I to a digit - any value 0 to 200 really
        $i = list2vec( 0 .. 199 );
      } elsif ( $opL == 0x33 ) {

        # BCD dump
        #if ( $i > 4093 ) {
        #die "I overflow";
        #}

        _d( "BCD of v[$opB] to I", $pc, $op, $i, $timer_delay, @v );

        foreach my $off ( vec2list($i) ) {
          if ( $ram[$off]{exec} || $ram[ $off + 1 ]{exec} || $ram[ $off + 2 ]{exec} ) {
            die "BCD Write to executable memory $off at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
          }
          $ram[$off]{write} = 1;
          $ram[$off]{ram} |= list2vec( 0 .. 2 );
          $ram[ $off + 1 ]{write} = 1;
          $ram[ $off + 1 ]{ram} |= list2vec( 0 .. 9 );
          $ram[ $off + 2 ]{write} = 1;
          $ram[ $off + 2 ]{ram} |= list2vec( 0 .. 9 );
        }
      } elsif ( $opL == 0x55 ) {

        # store N registers
        my @offsets = vec2list($i);

        _d( "STORE v[0] - v[$opB] to I", $pc, $op, $i, $timer_delay, @v );

        foreach my $off (@offsets) {
          for ( my $j = 0 ; $j <= $opB ; $j++ ) {
            if ( $ram[ $off + $j ]{exec} ) {
              die "Write to executable memory $off + $j at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
            }
            $ram[ $off + $j ]{write} = 1;
            $ram[ $off + $j ]{ram} |= $v[$opB];
          }
        }

        $i = list2vec( map { $_ + $opB + 1 } @offsets );
      } elsif ( $opL == 0x65 ) {

        # load N registers
        my @offsets = vec2list($i);

        _d( "LOAD v[0] - v[$opB] to I", $pc, $op, $i, $timer_delay, @v );

        for ( my $j = 0 ; $j <= $opB ; $j++ ) {
          $v[$j] = '';
          foreach my $off (@offsets) {
            $ram[ $off + $j ]{read} = 1;
            $v[$j] |= $ram[ $off + $j ]{ram};
          }
        }

        $i = list2vec( map { $_ + $opB + 1 } @offsets );
      } else {
        die "Illegal opcode at " . sprintf( "%03x", $pc ) . ", op = " . sprintf( "%04x", $op );
      }
      $pc += 2;
    }

  }
}

iterate( 0x200, undef, 0, [ ( list2vec(0) ) x 16 ] );

# C output
open my $c, '>', $ARGV[0] . '.c';

print $c "#include \"wrapper.h\"\n";
print $c "#include <stdint.h>\n";
print $c "#include <setjmp.h>\n";
print $c "#include <stdio.h>\n";
print $c "#include <stdlib.h>\n\n";
print $c "uint8_t SCREEN[32][64];\n";
print $c "uint8_t * i;\n";
print $c "uint8_t v[16];\n";
print $c "#define STACK_DEPTH 16\n";
print $c "jmp_buf stack[STACK_DEPTH];\n";
print $c "uint8_t sp = 0;\n";
print $c "uint8_t TIMER_DELAY = 0;\n";
print $c "uint8_t TIMER_SOUND = 0;\n\n";

print $c <<EOF;
static const unsigned char FONT[0x10 * 5] = {
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80  // F
};

// helper functions
static const uint8_t plot(uint8_t x, uint8_t y, uint8_t height) {
  uint8_t collision = 0;

  y %= 32;
  x %= 64;

  if (y + height > 32) height = 32 - y;
  for (uint8_t row = 0; row < height; row ++) {
    uint8_t width = 8;
    if (x + width > 64) width = 64 - x;
    for (uint8_t col = 0; col < width; col ++) {
      if (*(i + row) & (0x80 >> col)) {
        uint8_t p = ! SCREEN[y + row][x + col];
        SCREEN[y + row][x + col] = p;
        screen_set(x + col, y + row, p);
        if ( ! p) collision = 1;
      }
    }
  }

  screen_update();

  return collision;
}

static void clear() {
  memset(SCREEN, 0, 64 * 32);
  screen_clear();
}

EOF

my $start;
for ( my $i = 0x200 ; $i < 4096 ; $i++ ) {

  # identify contiguous read / write segments
  if ( $ram[$i]{read} || $ram[$i]{write} ) {

    # bit set - either mark this as the starting point
    if ( !defined $start ) {
      $start = $i;
      printf $c "uint8_t ram_%03x[] = { ", $i;
    } else {
      print $c ", ";
    }

    # or advance the endpoint
    printf $c "0x%02x", $ram[$i]{rom};
    $ram[$i]{block}  = $start;
    $ram[$i]{offset} = $i - $start;
  } elsif ( defined $start ) {
    print $c " };\n";

    # bit clear
    $start = undef;
  }
}

if ( defined $start ) {
  print $c " };\n";
  $start = undef;
}

print $c "void run() {\n clear();\n";

for ( my $i = 0x200 ; $i < 4096 ; $i++ ) {

  # decompile opcodes

  if ( $ram[$i]{exec} && $ram[$i]{exec}{nibble} == 1 ) {
    my $op = ( $ram[$i]{rom} << 8 ) | ( $ram[ $i + 1 ]{rom} );

    my $opA = ( ( $op & 0xF000 ) >> 12 );
    my $opB = ( ( $op & 0x0F00 ) >> 8 );
    my $opC = ( ( $op & 0x00F0 ) >> 4 );
    my $opD = ( $op & 0x000F );

    my $opL = ( $op & 0x00FF );

    my $opADDR = ( $op & 0x0FFF );

    printf $c "lbl_%03x:\n\t", $i;
    if ( $opA == 0 ) {

      # call machine routine
      if ( $opADDR == 0x0E0 ) {

        # screen clear - affects nothing
        print $c "screen_clear(); memset(SCREEN, 0, 64 * 32)\n";

      } elsif ( $opADDR == 0xEE ) {

        # RET - return the machine state
        print $c "if (sp == 0) { puts(\"Stack underflow\"); return; } longjmp(stack[sp - 1], 1);\n";
      }
    } elsif ( $opA == 1 ) {

      # infinite loop exits the program instead
      if ( $i != $opADDR ) {
        printf $c "goto lbl_%03x;\n", $opADDR;
      } else {
        printf $c "return;\n";
      }
    } elsif ( $opA == 2 ) {
      printf $c "if (sp == STACK_DEPTH) { puts(\"Stack overflow\"); return; } if (! setjmp(stack[sp])) { sp ++; goto lbl_%03x; } else sp --;\n", $opADDR;
    } elsif ( $opA == 3 ) {
      printf $c "if (v[0x%02x] == 0x%02x) goto lbl_%03x;\n", $opB, $opL, $i + 4;
    } elsif ( $opA == 4 ) {
      printf $c "if (v[0x%02x] != 0x%02x) goto lbl_%03x;\n", $opB, $opL, $i + 4;
    } elsif ( $opA == 5 ) {
      if ( $opD == 0 ) {
        printf $c "if (v[0x%02x] == v[0x%02x]) goto lbl_%03x;\n", $opB, $opC, $i + 4;
      }
    } elsif ( $opA == 6 ) {
      printf $c "v[0x%02x] = 0x%02x;\n", $opB, $opL;
    } elsif ( $opA == 7 ) {
      printf $c "v[0x%02x] += 0x%02x;\n", $opB, $opL;
    } elsif ( $opA == 8 ) {
      if ( $opD == 0 ) {
        printf $c "v[0x%02x] = v[0x%02x];\n", $opB, $opC;
      } elsif ( $opD == 1 ) {
        printf $c "v[0x%02x] |= v[0x%02x];\n\tv[0xF] = 0;\n", $opB, $opC;
      } elsif ( $opD == 2 ) {
        printf $c "v[0x%02x] &= v[0x%02x];\n\tv[0xF] = 0;\n", $opB, $opC;
      } elsif ( $opD == 3 ) {
        printf $c "v[0x%02x] ^= v[0x%02x];\n\tv[0xF] = 0;\n", $opB, $opC;
      } elsif ( $opD == 4 ) {
        printf $c "{ uint16_t result = v[0x%02x] + v[0x%02x];\n\tv[0x%02x] = result;\nv[0xF] = (result > 255 ? 1 : 0);}\n", $opB, $opC, $opB;
      } elsif ( $opD == 5 ) {
        printf $c "{ uint16_t result = v[0x%02x] - v[0x%02x];\n\tv[0x%02x] = result;\nv[0xF] = (result > 255 ? 0 : 1);}\n", $opB, $opC, $opB;
      } elsif ( $opD == 6 ) {
        printf $c "{ uint8_t bit = v[0x%02x] & 1;\n\tv[0x%02x] = v[0x%02x] >> 1;\nv[0xF] = bit;}\n", $opC, $opB, $opC;
      } elsif ( $opD == 7 ) {
        printf $c "{ uint16_t result = v[0x%02x] - v[0x%02x];\n\tv[0x%02x] = result;\nv[0xF] = (result > 255 ? 0 : 1);}\n", $opC, $opB, $opB;
      } elsif ( $opD == 0xE ) {
        printf $c "{ uint8_t bit = v[0x%02x] >> 7;\n\tv[0x%02x] = v[0x%02x] << 1;\nv[0xF] = bit;}\n", $opC, $opB, $opC;
      }
    } elsif ( $opA == 9 ) {
      if ( $opD == 0 ) {
        printf $c "if (v[0x%02x] != v[0x%02x]) goto lbl_%03x;\n", $opB, $opC, $i + 4;
      }
    } elsif ( $opA == 0xA ) {
      printf $c "i = ram_%03x + 0x%03x;\n", $ram[$opADDR]{block}, $ram[$opADDR]{offset};
    } elsif ( $opA == 0xB ) {
      die "ah";
    } elsif ( $opA == 0xC ) {
      printf $c "v[0x%02x] = rand() & 0x%02x;\n", $opB, $opL;
    } elsif ( $opA == 0xD ) {
      printf $c "v[0xF] = plot(v[0x%x], v[0x%x], 0x%02x);\n", $opB, $opC, $opD;
    } elsif ( $opA == 0xE ) {
      if ( $opL == 0x9E ) {
        printf $c "if (check_key(v[0x%02x])) goto lbl_%03x;\n", $opB, $i + 4;
      } elsif ( $opL == 0xA1 ) {
        printf $c "if (! check_key(v[0x%02x])) goto lbl_%03x;\n", $opB, $i + 4;
      }
    } elsif ( $opA == 0xF ) {
      if ( $opL == 0x07 ) {
        printf $c "v[0x%02x] = TIMER_DELAY;\n", $opB;
      } elsif ( $opL == 0x0A ) {
        printf $c "v[0x%02x] = await_key();\n", $opB;
      } elsif ( $opL == 0x15 ) {
        printf $c "TIMER_DELAY = v[0x%02x];\n", $opB;
      } elsif ( $opL == 0x18 ) {
        printf $c "TIMER_SOUND = v[0x%02x];\n", $opB;
      } elsif ( $opL == 0x1E ) {
        printf $c "i += v[0x%02x];\n", $opB;
      } elsif ( $opL == 0x29 ) {
        printf $c "i = & FONT[5 * (v[0x%02x] & 0xF)];\n", $opB;
      } elsif ( $opL == 0x33 ) {
        printf $c "{ unsigned char value = v[0x%02x];\n", $opB;
        printf $c "*(i + 2) = value %% 10; value /= 10;\n";
        printf $c "*(i + 1) = value %% 10; *i = value / 10;}\n";
      } elsif ( $opL == 0x55 ) {
        printf $c "for (unsigned char j = 0; j <= 0x%02x; j ++, i ++)\n", $opB;
        printf $c "\t\t*i = v[j];\n";
      } elsif ( $opL == 0x65 ) {
        printf $c "for (unsigned char j = 0; j <= 0x%02x; j ++, i ++)\n", $opB;
        printf $c "\t\tv[j] = *i;\n";
      }
    }
  }
}

print $c "}\n";
close $c;

# HTML output
open my $html, '>', "out.html";
print $html '<html><head><title>' . $ARGV[0] . '</title><body><h1>' . $ARGV[0] . '</h1>';

print $html '<table border="1"><tr><th>Color</th><th>Meaning</th></tr>';
print $html '<tr><td bgcolor="#C0C0C0">&nbsp;</td><td>Unused</td></tr>';
print $html '<tr><td bgcolor="#8080FF">&nbsp;</td><td>Exec</td></tr>';
print $html '<tr><td bgcolor="#80FF80">&nbsp;</td><td>Write</td></tr>';
print $html '<tr><td bgcolor="#FF8080">&nbsp;</td><td>Read</td></tr>';
print $html '<tr><td bgcolor="#80FFFF">&nbsp;</td><td>Write + Exec</td></tr>';
print $html '<tr><td bgcolor="#FF80FF">&nbsp;</td><td>Read + Exec</td></tr>';
print $html '<tr><td bgcolor="#FFFF80">&nbsp;</td><td>Read + Write</td></tr>';
print $html '<tr><td bgcolor="#FFFFFF">&nbsp;</td><td>Read + Write + Exec</td></tr>';
print $html '</table><hr><table border="1"><tr><th>&nbsp;</th>';

for ( my $i = 0 ; $i < 64 ; $i++ ) {
  print $html '<th>' . sprintf( "%02x", $i ) . '</th>';
}

print $html '</tr><tr><th>000</th><td colspan="64" rowspan="8" bgcolor="#808080">RESERVED</td></tr>';
for ( my $j = 1 ; $j < 8 ; $j++ ) {
  print $html "<tr><th>" . sprintf( "%03x", $j * 64 ) . "</th></tr>\n";
}
for ( my $j = 8 ; $j < 64 ; $j++ ) {
  print $html '<tr><th>' . sprintf( "%03x", $j * 64 ) . '</th>';
  for ( my $i = 0 ; $i < 64 ; $i++ ) {
    my $cell  = 64 * $j + $i;
    my $color = '';
    my $title = '';
    if ( !defined $ram[$cell] ) { $color = ' bgcolor="#C0C0C0"' }
    else {
      $color =
          ' bgcolor="#'
        . ( defined $ram[$cell]{read}  ? 'FF'                                             : '80' )
        . ( defined $ram[$cell]{write} ? 'FF'                                             : '80' )
        . ( defined $ram[$cell]{exec}  ? ( $ram[$cell]{exec}{nibble} == 1 ? 'FF' : 'C0' ) : '80' ) . '"';

      $title = ' title="Values: ' . vec2range( $ram[$cell]{ram} );
      if ( defined $ram[$cell]{exec} ) {
        my $cel = $cell;
        if ( $ram[$cell]{exec}{nibble} == 2 ) { $cel-- }
        if ( defined $msg_map[$cel] ) {
          $title .= "\n" . $msg_map[$cel];
        }
      }
      $title .= '"';
    }
    print $html '<td' . $color . $title . '>' . ( ( defined $ram[$cell] && defined $ram[$cell]{rom} ) ? sprintf( '%02x', $ram[$cell]{rom} ) : '-' ) . '</td>';
  }
  print $html "</tr>\n";
}
print $html '</table>';
close $html;

