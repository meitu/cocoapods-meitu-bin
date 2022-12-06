
module Pod
  class Command
    class Bin < Command
      class Source < Bin
        class Delete < Source

          self.summary = '删除二进制对应的源码'
          self.description = <<-DESC
            #{self.summary}
          DESC

          self.arguments = [
            CLAide::Argument.new('NAMES', true )
          ]

          def self.options
            [
              %w[--all 删除所有二进制对应的源码]
            ].concat(super).uniq
          end

          def initialize(argv)
            @names = argv.shift_argument
            @all = argv.flag?('all', false)
            super
          end

          def run
            if @names.nil? && !@all
              raise Informative, "请输入要删除的Pod库名（多个库中间用逗号分开）或者添加`--all`删除全部的源码"
            end
            if @all
              UI.puts "删除全部源码".yellow
              FileUtils.rm_rf(source_dir)
              UI.puts "删除完成".green
              return
            end
            unless @names.nil?
              name_arr = @names.split(',')
              name_arr.each do |name|
                UI.puts "删除`#{name}`".yellow
                dir = "#{source_dir}/#{name}"
                unless File.exist?(dir)
                  UI.puts "`#{name}`不存在".red
                  next
                end
                FileUtils.rm_rf(dir)
                UI.puts "删除`#{name}`成功".green
              end
            end
          end

        end
      end
    end
  end
end

