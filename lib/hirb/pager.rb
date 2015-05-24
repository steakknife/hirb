require 'shellwords'

module Hirb
  # This class provides class methods for paging and an object which can conditionally page given a terminal size that is exceeded.
  class Pager
    class<<self
      # Pages using a configured or detected shell command.
      def command_pager(output, options={})
        if valid_pager_command?(pc = options[:pager_command])
          basic_pager(output, pc)
        end
      end

      # Exposed to allow user-custom, external-driven formatting
      def basic_pager(output, override_pager_command=nil)
        pc = basic_pager_command(override_pager_command)
        pager = IO.popen(pc, "w")
        begin
          save_stdout = STDOUT.clone
          STDOUT.reopen(pager)
          STDOUT.puts output
        rescue Errno::EPIPE
        ensure
         STDOUT.reopen(save_stdout)
         save_stdout.close
         pager.close
        end
      end

      def pager_command=(*commands) #:nodoc:
        @pager_command = pager_command_select(*commands)
      end

      def pager_command #:nodoc:
        @pager_command || pager_command_select
      end

      # Pages with a ruby-only pager which either pages or quits.
      def default_pager(output, options={})
        pager = new(options[:width], options[:height])
        while pager.activated_by?(output, options[:inspect])
          puts pager.slice!(output, options[:inspect])
          return unless continue_paging?
        end
        puts output
        puts "=== Pager finished. ==="
      end

      def page(string, inspect_mode, pgr_cmd, width, height)
        if valid_pager_command?(pgr_cmd)
          command_pager(string, :pager_command=>pgr_cmd)
        else
          default_pager(string, :width=>width, :height=>height, :inspect=>inspect_mode)
        end
      end

      private

      #:stopdoc:
      def valid_pager_command?(cmd)
        cmd && Util.command_exists?(cmd.shellsplit[0])
      end

      # Default pager commands to try
      def pager_command_fallbacks #:nodoc:
        candidates = %w[less more pager cat]
        candidates.unshift ENV['PAGER'] if ENV['PAGER']
        candidates
      end

      # Pick the first valid command from commands
      def pager_command_select(*commands)
        commands += pager_command_fallbacks
        commands.flatten.compact.uniq.find { |c| valid_pager_command? c }
      end

      # Actual command basic_pager needs to perform
      def basic_pager_command(override_pager_command)
        if valid_pager_command?(override_pager_command)
          override_pager_command
        else
          pager_command
        end
      end

      def continue_paging?
        puts "=== Press enter/return to continue or q to quit: ==="
        !$stdin.gets.chomp[/q/i]
      end
      #:startdoc:
    end # class methods

    attr_reader :width, :height, :options

    def initialize(width, height, options={})
      resize(width, height)
      @options = options
    end

    def pager_command
      options[:pager_command] || self.class.pager_command
    end

    # Pages given string using configured pager.
    def page(string, inspect_mode)
      self.class.page(string, inspect_mode, pager_command, @width, @height)
    end

    def slice!(output, inspect_mode=false) #:nodoc:
      effective_height = @height - 2 # takes into account pager prompt
      if inspect_mode
        sliced_output = String.slice(output, 0, @width * effective_height)
        output.replace String.slice(output, char_count(sliced_output), String.size(output))
        sliced_output
      else
        # could use output.scan(/[^\n]*\n?/) instead of split
        sliced_output = output.split("\n").slice(0, effective_height).join("\n")
        output.replace output.split("\n").slice(effective_height..-1).join("\n")
        sliced_output
      end
    end

    # Determines if string should be paged based on configured width and height.
    def activated_by?(string_to_page, inspect_mode=false)
      inspect_mode ? (String.size(string_to_page) > @height * @width) : (string_to_page.count("\n") > @height)
    end

    if String.method_defined? :chars
      def char_count(string) #:nodoc:
        string.chars.count
      end
    else
      def char_count(string) #:nodoc:
        String.size(string)
      end
    end

    def resize(width, height) #:nodoc:
      @width, @height = View.determine_terminal_size(width, height)
    end
  end
end
