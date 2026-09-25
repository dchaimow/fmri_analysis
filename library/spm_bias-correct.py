#! /usr/bin/env python3
import sys
import os
import tempfile
from nipype.interfaces import spm,matlab


def spm_bias_correction():
    # bias correct INV2
    seg = spm.NewSegment()
    seg.inputs.channel_info = (0.001, 20, (False, True))
    seg.inputs.affine_regularization = 'mni'
    seg.inputs.sampling_distance = 3
    seg.inputs.warping_regularization = [0, 0.001, 0.5, 0.05, 0.2]
    seg.inputs.write_deformation_fields = [False, False]
    return seg
                          
if __name__ == "__main__":
    if len(sys.argv) == 3:
        matlab.MatlabCommand.set_default_paths(sys.argv[2])
    else:
        matlab_cmd = '/opt/spm12/run_spm12.sh /opt/mcr/v93 script'
        # nipype checks SPM by writing and running a matlab script (pyscript.m) in the current directory;
        # do this in a temporary directory, so that concurrent processes do not overwrite each other's script
        cwd = os.getcwd()
        with tempfile.TemporaryDirectory() as tmpdirname:
            os.chdir(tmpdirname)
            try:
                spm.SPMCommand.set_mlab_paths(matlab_cmd=matlab_cmd, use_mcr=True)
            finally:
                os.chdir(cwd)
        
    if len(sys.argv) in [2,3]:
        infile = sys.argv[1]
        bias_correct = spm_bias_correction()        
        bias_correct.inputs.channel_files = infile
        bias_correct.run(cwd=os.path.dirname(os.path.abspath(infile)))
    else:
        print('Usage: spm_bias-correct.py infile [spm_path]')
    
    
