import os
import re
import shutil
import subprocess
import shlex
import logging
import random
import string
from string import Template
import sys

import riscof.utils as utils
import riscof.constants as constants
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()

class kcore(pluginTemplate):
    __model__ = "kcore"
    __version__ = "1.0.0"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        config = kwargs.get('config')

        if config is None:
            print("Please enter input file paths in configuration.")
            raise SystemExit(1)

        # Get the directory where config.ini is located (riscof_targets directory)
        # RISCOF runs from this directory, so relative paths are resolved from here
        config_dir = os.getcwd()

        # Resolve paths - if relative, make them relative to config directory
        # If absolute, use as-is
        pluginpath_raw = config['pluginpath']
        if not os.path.isabs(pluginpath_raw):
            self.pluginpath = os.path.abspath(os.path.join(config_dir, pluginpath_raw))
        else:
            self.pluginpath = os.path.abspath(pluginpath_raw)

        self.num_jobs = str(config['jobs'] if 'jobs' in config else 1)

        ispec_raw = config['ispec']
        if not os.path.isabs(ispec_raw):
            self.isa_spec = os.path.abspath(os.path.join(config_dir, ispec_raw))
        else:
            self.isa_spec = os.path.abspath(ispec_raw)

        pspec_raw = config['pspec']
        if not os.path.isabs(pspec_raw):
            self.platform_spec = os.path.abspath(os.path.join(config_dir, pspec_raw))
        else:
            self.platform_spec = os.path.abspath(pspec_raw)

        # Get paths from project root
        self.project_root = os.path.abspath(os.path.join(self.pluginpath, '../../../'))

        # Load environment configuration
        env_config_path = os.path.join(self.project_root, 'env.config')
        self.riscv_prefix = None
        self.verilator_bin = None

        if os.path.exists(env_config_path):
            with open(env_config_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('RISCV_PREFIX='):
                        self.riscv_prefix = line.split('=', 1)[1]
                    elif line.startswith('VERILATOR='):
                        self.verilator_bin = line.split('=', 1)[1]

        if not self.riscv_prefix:
            self.riscv_prefix = 'riscv32-unknown-elf-'
        if not self.verilator_bin:
            self.verilator_bin = 'verilator'

        # Path to Verilator executable
        self.dut_exe = os.path.join(self.project_root, 'build/verilator/kcore_vsim')

        if 'target_run' in config and config['target_run']=='0':
            self.target_run = False
        else:
            self.target_run = True

    def initialise(self, suite, work_dir, archtest_env):
       self.work_dir = work_dir
       self.suite_dir = suite

       # Compile command using project's toolchain
       self.compile_cmd = self.riscv_prefix + 'gcc -march={0} \
         -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -g\
         -T '+self.pluginpath+'/env/link.ld\
         -I '+self.pluginpath+'/env/\
         -I ' + archtest_env + ' {2} -o {3} {4}'

    def build(self, isa_yaml, platform_yaml):
      ispec = utils.load_yaml(isa_yaml)['hart0']
      self.xlen = ('64' if 64 in ispec['supported_xlen'] else '32')

      self.isa = 'rv' + self.xlen
      if "I" in ispec["ISA"]:
          self.isa += 'i'
      if "M" in ispec["ISA"]:
          self.isa += 'm'
      if "A" in ispec["ISA"]:
          self.isa += 'a'
      if "F" in ispec["ISA"]:
          self.isa += 'f'
      if "D" in ispec["ISA"]:
          self.isa += 'd'
      if "C" in ispec["ISA"]:
          self.isa += 'c'
      if "Zicsr" in ispec["ISA"]:
          self.isa += '_zicsr'
      if "Zifencei" in ispec["ISA"]:
          self.isa += '_zifencei'

      self.compile_cmd = self.compile_cmd + ' -mabi=' + ('lp64 ' if 64 in ispec['supported_xlen'] else 'ilp32 ')

    def runTests(self, testList):
      if os.path.exists(self.work_dir + "/Makefile." + self.name[:-1]):
            os.remove(self.work_dir + "/Makefile." + self.name[:-1])

      make = utils.makeUtil(makefilePath=os.path.join(self.work_dir, "Makefile." + self.name[:-1]))
      make.makeCommand = 'make -k -j' + self.num_jobs

      for testname in testList:
          testentry = testList[testname]
          test = testentry['test_path']
          test_dir = testentry['work_dir']
          elf = os.path.join(test_dir, testname + '.elf')
          sig_file = os.path.join(test_dir, self.name[:-1] + ".signature")

          compile_macros = ' -D' + " -D".join(testentry['macros'])

          # Compile command
          cmd = self.compile_cmd.format(testentry['isa'].lower(), self.xlen, test, elf, compile_macros)

          if self.target_run:
            # Extract signature addresses from ELF using nm
            nm_cmd = self.riscv_prefix + 'nm {0} | grep -E "begin_signature|end_signature" > {1}.symbols; '.format(elf, elf)

            # Run on Verilator with signature extraction using ELF file directly
            # The signature extraction script will read the .symbols file and pass addresses to simulator
            # Pass RISCOF_DEBUG environment variable if set
            debug_prefix = ''
            if os.environ.get('RISCOF_DEBUG', '0') == '1':
                debug_prefix = 'export RISCOF_DEBUG=1; '

            simcmd = nm_cmd + debug_prefix + 'python3 {0}/extract_signature.py {1} {2}'.format(
                self.pluginpath, elf, sig_file)
          else:
            simcmd = 'echo "NO RUN"'

          execute = '@cd {0}; {1}; {2};'.format(test_dir, cmd, simcmd)
          make.add_target(execute)

      make.execute_all(self.work_dir)

      if not self.target_run:
          raise SystemExit(0)
