# frozen_string_literal: true

# Ruby scanner for the no-comments hook.
#
# The line scanner tracks single/double/backtick strings, #{} interpolation,
# % literals and heredoc bodies so a '#' inside data is not read as a comment.
# Ambiguity resolves toward silence: a missed comment is a review finding, a
# false deny is a blocked agent.

module NoComments
  module Languages
    module Ruby
      NAME = "ruby"
      ALIASES = %w[ruby rb].freeze

      PATHS = /\.(?:rb|rake)\z/
      EXCLUDED = %r{/vendor/(?:bundle|gems)/|/db/schema\.rb\z|_pb\.rb\z}
      MARKERS = %w[Gemfile].freeze

      ADVICE = "extract it into a well-named method and let the name carry " \
               "the meaning."

      PRAGMA = /\A\#\s*(?:
                  !                              |  # shebang
                  frozen_string_literal\s*:      |
                  (?:en)?coding\s*[:=]           |
                  -\*-                           |  # emacs modeline
                  typed\s*:                      |  # sorbet
                  rubocop\s*:                    |
                  :\s*no(?:doc|cov)\s*:
                )/x

      HEREDOC = /<<([-~])?(["'`]?)([A-Z_][A-Z0-9_]*)\2/

      PERCENT_CLOSE = { "[" => "]", "(" => ")", "{" => "}", "<" => ">" }.freeze

      module_function

      # Comment lines in a chunk of source, skipping heredoc bodies and =begin
      # blocks' interiors (the =begin/=end pair itself is one comment).
      def comments(text)
        found = []
        pending = []
        block = false

        text.to_s.each_line do |raw|
          line = raw.chomp

          if pending.any?
            pending.shift if line.strip == pending.first
            next
          end

          if block
            block = false if line.start_with?("=end")
            next
          end

          if line.start_with?("=begin")
            block = true
            found << line
            next
          end

          comment = comment_at(line)
          found << comment.strip if comment && !comment.match?(PRAGMA)

          line.scan(HEREDOC) { |_, _, id| pending << id }
        end

        found
      end

      # Comment text on a line, or nil. Walks the line so a '#' inside a
      # string, an interpolation, or a % literal is not mistaken for a comment
      # start.
      def comment_at(line)
        i = 0
        prev = nil
        while i < line.length
          c = line[i]
          case c
          when "'", '"', "`"
            i = skip_string(line, i, c)
            prev = nil
            next
          when "%"
            skipped = skip_percent_literal(line, i, prev)
            if skipped
              i = skipped
              prev = nil
              next
            end
          when "#"
            return line[i..] if prev.nil? || prev.match?(/\s/)
          end
          prev = c
          i += 1
        end
        nil
      end

      # End of a %w[]/%q()/%r{} literal starting at start, or nil when this '%'
      # is modulo. Only a '%' that opens an expression can start a literal,
      # which keeps 'total % count' out of it.
      def skip_percent_literal(line, start, prev)
        return nil unless prev.nil? || prev.match?(/[\s(\[{,=]/)

        rest = line[start..]
        m = rest.match(/\A%[qQwWiIrs]?([^\sA-Za-z0-9])/)
        return nil unless m

        open = m[1]
        close = PERCENT_CLOSE[open] || open
        depth = 1
        i = start + m[0].length
        while i < line.length
          case line[i]
          when "\\" then i += 1
          when open then depth += 1 if close != open
          when close
            depth -= 1
            return i + 1 if depth.zero?
          end
          i += 1
        end
        i
      end

      def skip_string(line, start, quote)
        i = start + 1
        while i < line.length
          case line[i]
          when "\\"
            i += 2
            next
          when quote
            return i + 1
          when "#"
            if quote != "'" && line[i + 1] == "{"
              i = skip_interpolation(line, i + 2)
              next
            end
          end
          i += 1
        end
        i
      end

      def skip_interpolation(line, start)
        depth = 1
        i = start
        while i < line.length && depth.positive?
          case line[i]
          when "{" then depth += 1
          when "}" then depth -= 1
          end
          i += 1
        end
        i
      end
    end
  end
end
