class Cppcheck < Formula
  desc "Static analysis of C and C++ code"
  homepage "https://sourceforge.net/projects/cppcheck/"
  url "https://github.com/danmar/cppcheck/archive/1.76.tar.gz"
  sha256 "e8a75211a111a27d1e6b98f93c7c9480ba58ec9201efe092c7ac075cd98ca091"
  head "https://github.com/danmar/cppcheck.git"

  bottle do
    sha256 "9c062032badd5bf2d1885e5a371de194c6db249cc1b752affa313424c5ed544b" => :sierra
    sha256 "489e1c5852a286f470fef07e3c6bcd9ea3bc472ced5215846393aadf3197fa58" => :el_capitan
    sha256 "4784172776ef6ac4dff2476bb117c75fe161f0bb8d9bed74bc00b276b7de1599" => :yosemite
  end

  option "without-rules", "Build without rules (no pcre dependency)"
  option "with-qt5", "Build the cppcheck GUI (requires Qt)"

  deprecated_option "no-rules" => "without-rules"
  deprecated_option "with-gui" => "with-qt5"

  depends_on "pcre" if build.with? "rules"
  depends_on "qt5" => :optional

  needs :cxx11

  def install
    ENV.cxx11

    # Man pages aren't installed as they require docbook schemas.

    # Pass to make variables.
    if build.with? "rules"
      system "make", "HAVE_RULES=yes", "CFGDIR=#{prefix}/cfg"
    else
      system "make", "HAVE_RULES=no", "CFGDIR=#{prefix}/cfg"
    end

    # CFGDIR is relative to the prefix for install, don't add #{prefix}.
    system "make", "DESTDIR=#{prefix}", "BIN=#{bin}", "CFGDIR=/cfg", "install"

    # Move the python addons to the cppcheck pkgshare folder
    (pkgshare/"addons").install Dir.glob(bin/"*.py")

    if build.with? "qt5"
      cd "gui" do
        if build.with? "rules"
          system "qmake", "HAVE_RULES=yes",
                          "INCLUDEPATH+=#{Formula["pcre"].opt_include}",
                          "LIBS+=-L#{Formula["pcre"].opt_lib}"
        else
          system "qmake", "HAVE_RULES=no"
        end

        system "make"
        prefix.install "cppcheck-gui.app"
      end
    end
  end

  test do
    # Execution test with an input .cpp file
    test_cpp_file = testpath/"test.cpp"
    test_cpp_file.write <<-EOS.undent
      #include <iostream>
      using namespace std;

      int main()
      {
        cout << "Hello World!" << endl;
        return 0;
      }

      class Example
      {
        public:
          int GetNumber() const;
          explicit Example(int initialNumber);
        private:
          int number;
      };

      Example::Example(int initialNumber)
      {
        number = initialNumber;
      }
    EOS
    system "#{bin}/cppcheck", test_cpp_file

    # Test the "out of bounds" check
    test_cpp_file_check = testpath/"testcheck.cpp"
    test_cpp_file_check.write <<-EOS.undent
      int main()
      {
      char a[10];
      a[10] = 0;
      return 0;
      }
    EOS
    output = shell_output("#{bin}/cppcheck #{test_cpp_file_check} 2>&1")
    assert_match "out of bounds", output

    # Test the addon functionality: sampleaddon.py imports the cppcheckdata python
    # module and uses it to parse a cppcheck dump into an OOP structure. We then
    # check the correct number of detected tokens and function names.
    addons_dir = pkgshare/"addons"
    cppcheck_module = "#{name}data"
    expect_token_count = 55
    expect_function_names = "main,GetNumber,Example"
    assert_parse_message = "Error: sampleaddon.py: failed: can't parse the #{name} dump."

    sample_addon_file = testpath/"sampleaddon.py"
    sample_addon_file.write <<-EOS.undent
      #!/usr/bin/env python
      """A simple test addon for #{name}, prints function names and token count"""
      import sys
      import imp
      # Manually import the '#{cppcheck_module}' module
      CFILE, FNAME, CDATA = imp.find_module("#{cppcheck_module}", ["#{addons_dir}"])
      CPPCHECKDATA = imp.load_module("#{cppcheck_module}", CFILE, FNAME, CDATA)

      for arg in sys.argv[1:]:
          # Parse the dump file generated by #{name}
          configKlass = CPPCHECKDATA.parsedump(arg)
          if len(configKlass.configurations) == 0:
              sys.exit("#{assert_parse_message}") # Parse failure
          fConfig = configKlass.configurations[0]
          # Pick and join the function names in a string, separated by ','
          detected_functions = ','.join(fn.name for fn in fConfig.functions)
          detected_token_count = len(fConfig.tokenlist)
          # Print the function names on the first line and the token count on the second
          print "%s\\n%s" %(detected_functions, detected_token_count)
    EOS

    system "#{bin}/cppcheck", "--dump", test_cpp_file
    test_cpp_file_dump = "#{test_cpp_file}.dump"
    assert File.exist? test_cpp_file_dump
    python_addon_output = shell_output "python #{sample_addon_file} #{test_cpp_file_dump}"
    assert_match "#{expect_function_names}\n#{expect_token_count}", python_addon_output
  end
end
