
require 'cocoapods-mtxx-bin/config/config'
require 'cocoapods-mtxx-bin/native/podfile'

module Pod
  class Command
    class Bin < Command
      class Repo < Bin
        class Push < Repo
          self.summary = '发布组件'
          self.description = <<-DESC
            #{self.summary}
            跳过lint过程
          DESC

          self.arguments = [
            CLAide::Argument.new('REPO', true ),
            CLAide::Argument.new('NAME.podspec', false )
          ]

          def self.options
            [].concat(Pod::Command::Repo::Push.options).concat(super).uniq
          end

          def initialize(argv)
            @repo = argv.shift_argument
            @podspec = argv.shift_argument
            super

            @additional_args = argv.remainder!
          end

          def run
            argvs = [
              @repo,
              *@additional_args
            ]

            push = Pod::Command::Repo::Push.new(CLAide::ARGV.new(argvs))
            push.validate!
            push.run
          ensure
            clear_binary_spec_file_if_needed unless @reserve_created_spec
          end

          private

          # def template_spec_file
          #   @template_spec_file ||= begin
          #                             if @template_podspec
          #                               find_spec_file(@template_podspec)
          #                             else
          #                               binary_template_spec_file
          #                             end
          #                           end
          # end
          #
          # def spec_file
          #   @spec_file ||= begin
          #                    if @podspec
          #                      find_spec_file(@podspec)
          #                    else
          #                      if code_spec_files.empty?
          #                        raise Informative, '当前目录下没有找到可用源码 podspec.'
          #                      end
          #
          #                      spec_file = if @binary
          #                                    code_spec = Pod::Specification.from_file(code_spec_files.first)
          #                                    if template_spec_file
          #                                      template_spec = Pod::Specification.from_file(template_spec_file)
          #                                    end
          #                                    create_binary_spec_file(code_spec, template_spec)
          #                                  else
          #                                    code_spec_files.first
          #                                  end
          #                      spec_file
          #                    end
          #                  end
          # end
          #
          # def repo
          #   @binary ? binary_source.name : code_source_list.first.name
          # end
        end
      end
    end
  end
end