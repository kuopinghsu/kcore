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

class rv32sim(pluginTemplate):
    __model__ = "rv32sim"
    __version__ = "1.0.0"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get('config')

        if config is None:
            logger.error("Config file is missing for rv32sim")
            raise SystemExit(1)

        # Get the directory where config.ini is located (riscof_targets directory)
        # RISCOF runs from this directory, so relative paths are resolved from here
        config_dir = os.getcwd()

        # Resolve pluginpath - if relative, make it relative to config directory
        pluginpath_raw = config['pluginpath']
        if not os.path.isabs(pluginpath_raw):
            self.pluginpath = os.path.abspath(os.path.join(config_dir, pluginpath_raw))
        else:
            self.pluginpath = os.path.abspath(pluginpath_raw)

        self.num_jobs = str(config['jobs'] if 'jobs' in config else 1)

        # Resolve ISA spec path
        ispec_raw = config['ispec']
        if not os.path.isabs(ispec_raw):
            self.isa_spec = os.path.abspath(os.path.join(config_dir, ispec_raw))
        else:
            self.isa_spec = os.path.abspath(ispec_raw)

        # Resolve platform spec path
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
        self.rv32sim_exe = os.path.join(self.project_root, 'build', 'rv32sim')

        if os.path.exists(env_config_path):
            with open(env_config_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('RISCV_PREFIX='):
                        self.riscv_prefix = line.split('=', 1)[1]

        if not self.riscv_prefix:
            self.riscv_prefix = 'riscv32-unknown-elf-'

        self.objdump_exe = self.riscv_prefix + 'objdump'
        self.dut_exe = self.rv32sim_exe
        self.num_jobs = str(config['jobs'] if 'jobs' in config else 1)
        
        # Check if target should be run
        if 'target_run' in config and config['target_run']=='0':
            self.target_run = False
        else:
            self.target_run = True
            
        logger.debug("rv32sim plugin initialized")

    def initialise(self, suite, work_dir, archtest_env):
        self.suite = suite
        self.work_dir = work_dir
        self.archtest_env = archtest_env
        self.objdump = self.objdump_exe + ' -D'

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

        # rv32sim ISA string - only supports rv32ima or rv32ima_zicsr
        # Remove _zifencei as rv32sim doesn't accept it in --isa parameter
        self.isa_sim = self.isa.replace('_zifencei', '')

        # Set ABI based on xlen and build compile_cmd
        # Format will be used later: {0}=test_path, {1}=elf_path, {2}=compile_macros
        abi = 'lp64' if "64" in self.xlen else 'ilp32'
        self.compile_cmd = self.riscv_prefix+'gcc -march='+self.isa.lower()+' -mabi='+abi+' \
         -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -g\
         -T '+self.pluginpath+'/env/link.ld \
         -I '+self.pluginpath+'/env/\
         -I '+self.archtest_env+' {0} -o {1} {2}'

    def runTests(self, testList):
        make = utils.makeUtil(makefilePath=os.path.join(self.work_dir, "Makefile." + self.name[:-1]))
        make.makeCommand = 'make -j' + self.num_jobs
        for testname in testList:
            testentry = testList[testname]
            test = testentry['test_path']
            test_dir = testentry['work_dir']
            elf = os.path.join(test_dir, self.name[:-1] + ".elf")
            sig_file = os.path.join(test_dir, self.name[:-1] + ".signature")

            # Compile macros
            compile_macros = ' -D' + " -D".join(testentry['macros'])

            # Compile command - using the base compile_cmd with proper formatting
            cmd = self.compile_cmd.format(test, elf, compile_macros)

            # rv32sim run command - using +signature to dump signature
            # The rv32sim will automatically detect begin_signature/end_signature symbols
            # and write the signature when it exits (via tohost)
            sim_cmd = '{0} --isa={1} +signature={2} +signature-granularity=4 {3}'.format(
                self.rv32sim_exe, self.isa_sim, sig_file, elf)

            execute = '@cd {0}; {1}; {2} &> {3}.log'.format(test_dir, cmd, sim_cmd, sig_file)
            make.add_target(execute)

        make.execute_all(self.work_dir)
