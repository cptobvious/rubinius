require "rake"
require "rake/tasklib"
require "tempfile"

class Field
  attr_reader :name
  attr_reader :type
  attr_reader :offset

  def initialize(name, type)
    @name = name
    @type = type
    @offset = nil
  end

  def offset=(o)
    @offset = o
  end
end

class StructGenerator
  def initialize
    @struct_name = nil
    @includes = []
    @fields = []
  end

  def self.generate_from_code(code)
    sg = StructGenerator.new
    sg.instance_eval(code)
    sg.layout
  end

  def name(n)
    @struct_name = n
  end

  def include(i)
    @includes << i
  end

  def field(name, type)
    @fields << Field.new(name, type)
  end

  def layout
    binary = "rb_struct_gen_bin_#{Process.pid}"

    Tempfile.open("rbx_struct_gen_tmp") do |f|
      f.puts "#include <stdio.h>"

      @includes.each do |inc|
        f.puts "#include <#{inc}>"
      end

      f.puts "#include <stddef.h>\n\n"
      f.puts "int main(int argc, char **argv)\n{"

      @fields.each do |field|
        f.puts <<EOF
  printf("%s %u\\n", "#{field.name}", offsetof(#{@struct_name}, #{field.name}));
EOF
      end

      f.puts "\n\treturn 0;\n}"
      f.flush

      `gcc -x c -Wall #{f.path} -o #{binary}`
    end

    output = `./#{binary}`
    File.unlink(binary)

    line_no = 0

    output.each_line do |line|
      md = line.match(/.+ (\d+)/)
      @fields[line_no].offset = md.captures.first.to_i

      line_no += 1
    end

    buf = ""

    @fields.each_with_index do |field, i|
      if buf.empty?
        buf << "layout :#{field.name}, :#{field.type}, #{field.offset}"
      else
        buf << "       :#{field.name}, :#{field.type}, #{field.offset}"
      end

      if i < @fields.length - 1
        buf << ",\n"
      end
    end

    buf
  end
end

module Rake
  class StructGeneratorTask < TaskLib
    attr_accessor :dest

    def initialize
      @dest = nil

      yield self if block_given?

      define
    end

    def field(name, type)
      @fields << Field.new(name, type)
    end

    def define
      task :clean do
        rm_f @dest
      end

      file @dest => "#{@dest}.in" do |t|
        puts "Generating #{@dest}..."

        File.open(t.name, "w") do |f|
          f.puts "# This file is generated by rake. Do not edit."
          f.puts

          in_sg = false
          sg_code = nil

          IO.foreach(t.prerequisites.first) do |line|
            md = line.match(/(\s*)@@@/)
            if md.nil?
              if in_sg
                sg_code ||= []
                sg_code << line
              else
                f.puts line
              end

              next
            end

            if in_sg
              sg_code = sg_code.join("\n")
              f.puts StructGenerator.generate_from_code(sg_code)
              sg_code = []
            end

            in_sg = !in_sg
          end
        end
      end
    end
  end
end
