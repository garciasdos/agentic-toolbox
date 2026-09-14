# frozen_string_literal: true

module NoComments
  module Languages
    module JavaScript
      NAME = "javascript"
      ALIASES = %w[javascript js jsx typescript ts tsx node].freeze

      PATHS = /\.(?:[cm]?js|[cm]?ts|jsx|tsx)\z/
      EXCLUDED = %r{
        /(?:node_modules|dist|build|out|coverage|\.next|\.nuxt|__generated__)/ |
        \.d\.[cm]?ts\z                                                        |
        \.min\.js\z                                                           |
        \.generated\.[cm]?[jt]sx?\z
      }x

      TYPESCRIPT_PATHS = /\.(?:ts|tsx|mts|cts)\z/
      MARKERS = %w[package.json tsconfig.json deno.json deno.jsonc jsr.json].freeze

      ADVICE = "extract it into a well-named function and let the name carry " \
               "the meaning. A JSDoc block restating a signature is the same " \
               "noise twice over: the types already say it."

      LINE_PRAGMA = %r{\A//[/!\#@]?\s*(?:
                         @ts-                          |
                         <reference                    |
                         eslint-                       |
                         biome-ignore                  |
                         oxlint-disable                |
                         deno-lint-ignore              |
                         dprint-ignore                 |
                         tslint:                       |
                         prettier-ignore               |
                         (?:istanbul|c8|v8)\s+ignore   |
                         codecov                       |
                         sourceMappingURL              |
                         @sourceURL                    |
                         @flow                         |
                         \$FlowFixMe                   |
                         @generated                    |
                         @jsx                          |
                         @__PURE__                     |
                         @license                      |
                         @preserve
                       )}x

      BLOCK_PRAGMA = %r{\A/\*[*!]?\s*(?:
                          eslint-                       |
                          eslint-env                    |
                          globals?\s                    |
                          @jsx                          |
                          webpack[A-Za-z]*\s*:          |
                          @vite-ignore                  |
                          \#?__PURE__                   |
                          @__PURE__                     |
                          (?:istanbul|c8|v8)\s+ignore   |
                          prettier-ignore               |
                          @flow                         |
                          @generated                    |
                          @license                      |
                          @preserve
                        )}x

      MINIFIER_PRESERVED_BANNER = "/*!"

      COMPILER_DIRECTIVE_ANYWHERE_IN_BLOCK = %r{(?:\A|[\s*/])@ts-[a-z-]+}

      TAGS_MEANINGFUL_IN_TYPESCRIPT =
        /(?:\A|[\s*])@(?:internal|deprecated|import|overload|satisfies)\b/

      TAGS_MEANINGFUL_ONLY_WHERE_JSDOC_IS_THE_TYPE_SYSTEM =
        /(?:\A|[\s*])@(?:type|typedef|callback|param|returns?|template|
                        enum|this|extends|implements|abstract|readonly|
                        property|prop|augments|throws|yields|constructor|
                        namespace)\b/x

      PUNCTUATION_BEFORE_REGEX = "(,=:[!&|?{};+-*%~^<>"

      KEYWORDS_BEFORE_REGEX = %w[
        return typeof case in of new delete void instanceof yield await throw
        else do
      ].freeze

      TRAILING_IDENTIFIER = /([A-Za-z_$][A-Za-z0-9_$]*)\s*\z/

      SKIPPED_LITERAL = "\0"

      LONGEST_REPORTED_COMMENT = 96

      module_function

      def comments(text, path = "")
        src = text.to_s
        found = []
        previous = nil
        index = 0

        while index < src.length
          char = src[index]
          following = src[index + 1]

          if char == "/" && following == "/"
            body, index = read_to_end_of_line(src, index)
            found << flattened(body) unless machine_read_line?(body)
            next
          end

          if char == "/" && following == "*"
            body, index = read_block(src, index)
            found << flattened(body) unless machine_read_block?(body, path)
            next
          end

          if char == "#" && following == "!" && index.zero?
            _, index = read_to_end_of_line(src, index)
            next
          end

          case char
          when "'", '"'
            index = skip_quoted(src, index, char)
            previous = SKIPPED_LITERAL
            next
          when "`"
            index = skip_template(src, index)
            previous = SKIPPED_LITERAL
            next
          when "/"
            after_literal = opens_regex_literal?(previous, src, index) ? end_of_regex_literal(src, index) : nil
            if after_literal
              index = after_literal
              previous = SKIPPED_LITERAL
              next
            end
          end

          previous = char unless char.match?(/\s/)
          index += 1
        end

        found
      end

      def machine_read_line?(body)
        body.match?(LINE_PRAGMA) || body.match?(COMPILER_DIRECTIVE_ANYWHERE_IN_BLOCK)
      end

      def machine_read_block?(body, path)
        return true if body.start_with?(MINIFIER_PRESERVED_BANNER)
        return true if body.match?(BLOCK_PRAGMA)
        return true if body.match?(COMPILER_DIRECTIVE_ANYWHERE_IN_BLOCK)
        return true if body.match?(TAGS_MEANINGFUL_IN_TYPESCRIPT)

        jsdoc_is_the_type_system?(path) &&
          body.match?(TAGS_MEANINGFUL_ONLY_WHERE_JSDOC_IS_THE_TYPE_SYSTEM)
      end

      def jsdoc_is_the_type_system?(path)
        !path.to_s.match?(TYPESCRIPT_PATHS)
      end

      def read_to_end_of_line(src, start)
        stop = src.index("\n", start) || src.length
        [src[start...stop], stop]
      end

      def read_block(src, start)
        close = src.index("*/", start + 2)
        stop = close ? close + 2 : src.length
        [src[start...stop], stop]
      end

      def skip_quoted(src, start, quote)
        index = start + 1

        while index < src.length
          case src[index]
          when "\\" then index += 2
          when quote then return index + 1
          when "\n" then return index
          else index += 1
          end
        end

        index
      end

      def skip_template(src, start)
        index = start + 1

        while index < src.length
          case src[index]
          when "\\"
            index += 2
          when "`"
            return index + 1
          when "$"
            index = src[index + 1] == "{" ? skip_interpolation(src, index + 2) : index + 1
          else
            index += 1
          end
        end

        index
      end

      def skip_interpolation(src, start)
        depth = 1
        index = start

        while index < src.length && depth.positive?
          case src[index]
          when "'", '"' then index = skip_quoted(src, index, src[index])
          when "`" then index = skip_template(src, index)
          when "{"
            depth += 1
            index += 1
          when "}"
            depth -= 1
            index += 1
          else index += 1
          end
        end

        index
      end

      def end_of_regex_literal(src, start)
        index = start + 1
        inside_character_class = false

        while index < src.length
          case src[index]
          when "\n" then return nil
          when "\\" then index += 2
          when "["
            inside_character_class = true
            index += 1
          when "]"
            inside_character_class = false
            index += 1
          when "/"
            return index + 1 unless inside_character_class

            index += 1
          else index += 1
          end
        end

        nil
      end

      def opens_regex_literal?(previous, src, index)
        return true if previous.nil?
        return true if PUNCTUATION_BEFORE_REGEX.include?(previous)

        identifier = src[0...index].match(TRAILING_IDENTIFIER)
        identifier ? KEYWORDS_BEFORE_REGEX.include?(identifier[1]) : false
      end

      def flattened(body)
        one_line = body.gsub(/\s+/, " ").strip
        return one_line if one_line.length <= LONGEST_REPORTED_COMMENT

        "#{one_line[0, LONGEST_REPORTED_COMMENT]}…"
      end
    end
  end
end
