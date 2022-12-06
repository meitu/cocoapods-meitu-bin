
module Pod
  class Command
    class Bin < Command
      class Source < Bin
        class List < Source

          SPECIAL_DIRS = %w[. .. .DS_Store].freeze

          self.summary = '打印二进制对应的源码'
          self.description = <<-DESC
            #{self.summary}
          DESC

          self.arguments = [
            CLAide::Argument.new('NAMES', true )
          ]

          def initialize(argv)
            @names = argv.shift_argument
            super
          end

          def run
            entries = Dir.entries(source_dir).reject { |dir| SPECIAL_DIRS.include?(dir) }
            unless @names.nil?
              name_arr = @names.split(',').map(&:downcase)
              entries.select! { |entry| name_arr.include?(entry.downcase) }
            end
            if entries.empty?
              UI.puts "无对应的源码".red
              return
            end
            entries.map do |entry|
              UI.puts "#{entry}".green
              sub_dir = "#{source_dir}/#{entry}"
              sub_entries = Dir.entries(sub_dir).reject { |dir| SPECIAL_DIRS.include?(dir) }
              sub_entries.map { |sub_entry| UI.puts " - #{sub_entry}".yellow }
            end
          end

        end
      end
    end
  end
end
