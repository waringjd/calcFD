function [fd,subjects] = calcFD(subjects,subjectpath,options)
% Calculate the fractal dimensionality of a 3D structure.
% Designed to work with intermediate files from FreeSurfer analysis pipeline
%   (ribbon.mgz, aparc.a2009s+aseg.mgz).
% Also can use other mgz volume as input (e.g., see 'benchmark folder').
% 
% See 'wrapper_sample.m' for an example of how to use the calcFD toolbox.
%
% REQUIRED INPUTS:
% subjects      = list of subjects names in a cell array
%                 alternatively accepts {'.'} to run on all subjects in folder
%
% subjectpath   = FreeSurfer 'SUBJECTDIR' where standard directory structure is
%
% options       = specify details of running the analysis
%
% options.alg   = 'dilate' | 'boxcount'
%
% options.countFilled = 0 | 1
%                       0   == Surface-only (FDs)
%                       1   == Filled volume (FDf)
%
% options.aparc = 'Ribbon' | 'Dest_aparc' | 'Dest_select' | 'DKT' | 'none'
%                 'Ribbon'      == Cortical Ribbon (unparcellated)
%                 'Dest_aparc'  == Parcellated cortical regions (Destrieux) 
%                                   ** requires options.input.
%                 'Dest_select' == Any region in the aparc.a2009s+aseg.mgz volume, 
%                                   ** requires options.input.
%                 'DKT'         == Parcellated cortical regions (DKT).
%                                   ** requires aparc.DKTaltas40+aseg.mgz to exist.
%                                   The volume can be generated using:
%                                   mri_aparc2aseg --s [SUBJECTID] --annot aparc.DKTatlas40
%                                   See Madan & Kensinger (2017, Brain Informatics) for further details. 
%                 'none'        == Binarized volume to be manually entered 
%                                   (e.g., benchmark volumes).
%
% options.input = filename string, required for 'Dest_aparc' and 'Dest_select
%               if options.aparc == 'Dest_aparc'
%                   This should be a file with the name 'mask_*.txt', 
%                       where * is the value in options.input.
%                   File should have either 74 or 148 rows, only 1 column.
%                       If only 74 values, labels are assigned bilaterally.
%                   Value in each row is the label to assign to that parcellated region, 
%                       based on the Destrieux et al. (2010) parcellation scheme.
%                   See 'mask_lobe.txt' for an example.
%                   See 'calcFD_mask.xlsx' for a list of which regions correspond to each row number.
%               --
%               if options.aparc == 'Dest_select'
%                   This should be a file with the name 'select_*.txt', 
%                       where * is the value in options.input.
%                   Regions correspond to intensity values in aparc.a2009s+aseg.mgz.
%                   See FreeSurfer files (e.g., FreeSurferColorLUT.txt, ASegStatsLUT.txt, 
%                       WMParcStatsLUT.txt) for mapping of region intensities to names.
%                   Multiple region values on the same row will be processed as a single structure.
%                   Currently cannot use the same region in more than one row,
%                       if need to violate this, use multiple input text files.
%                   See 'select_subcort.txt' and 'select_ventricles.txt' for examples.
% 
% options.output = filename string to output FD values to
%
%
% OPTIONAL INPUTS:
% options.boxsizes = list of numbers
%                    Default: 2.^[0:4] (resolves to [1,2,4,8,16])
%                    Specify what 'box sizes' (also applies to dilation algorithm) to use 
%                    when calculating FD.
%                    Preferred to scale in powers of two.
%
% ----
%
% The calcFD toolbox is available from: http://cmadan.github.io/calcFD/.
% 
% Please cite this paper if you use the toolbox:
%   Madan, C. R., & Kensinger, E. A. (2016). Cortical complexity as a measure of 
%       age-related brain atrophy. NeuroImage, 134, 617-629.
%       doi:10.1016/j.neuroimage.2016.04.029
%
% If you use the toolbox with subcortical/ventricular structures, please also cite:
%   Madan, C. R., & Kensinger, E. A. (2017). Age-related differences in the structural 
%       complexity of subcortical and ventricular structures. Neurobiology of Aging, 50, 87-95. 
%       doi:10.1016/j.neurobiolaging.2016.10.023
%
% 
% 20160616 CRM
% build 28

% process optional inputs
if ~isfield(options,'boxsizes')
    options.boxsizes = 2.^[0:4];
    % resolves to [1,2,4,8,16]
end

% get full list of subjects if asked
if strcmp(subjects{1},'.');
    list = dir(fullfile(subjectpath));
    list = {list([list.isdir]).name};
    
    % excl the non-subject folders
    excl = [1:2 find(cellfun(@length,strfind(list,'average')))];
    list = list(setdiff(1:length(list),excl));
    subjects = list;
elseif length(strfind(subjects{1},'*'))==1
    % subjects name has a wildcard, but only expect one entry then
    list = dir(fullfile(subjectpath,subjects{1}));
    list = {list([list.isdir]).name};
    subjects = list;
end

% error handling
if ~exist('strlen')
    disp('MATLAB-FreeSurfer functions not found in MATLAB path.')
    disp('Please see https://surfer.nmr.mgh.harvard.edu/fswiki/UserContributions/FAQ#FreeSurfer.26Matlab')
end

for s = 1:length(subjects)
    fprintf('Calculating FD for subject %s...',subjects{s})
    failed = 0;
    % load the desired aparc
    switch options.aparc
        case {'ribbon','Ribbon'}
            vol_fname = fullfile(subjectpath,subjects{s},'mri','ribbon.mgz');
            vol = load_mgh(vol_fname);
            % in cortical ribbon, GM = 42/3
            vol = (vol==3) | (vol==42);
            labels = 1;
                        
        case 'Dest_aparc'
            vol_fname = fullfile(subjectpath,subjects{s},'mri','aparc.a2009s+aseg.mgz');
            vol = load_mgh(vol_fname);
            labels = unique(vol);
            labels = labels(labels>10000);
            
            % load mask assignment
            mask = load(['mask_' options.input '.txt']);
            if length(mask) == 74
                % duplicate for other hemi
                mask = [ mask; mask ];
            end
            
            % reassign intensities using mask
            vol_mask = zeros(size(vol));
            for l = labels'
                vol_mask(vol==l) = mask(labels==l);
            end
            
            % replace vol with vol_mask
            vol = vol_mask;
            labels = unique(vol);
            labels = setdiff(labels,0);
            
        case 'Dest_select'
            vol_fname = fullfile(subjectpath,subjects{s},'mri','aparc.a2009s+aseg.mgz');
            vol = load_mgh(vol_fname);
            labels = unique(vol);
            
            % load select assignment
            select = load(['select_' options.input '.txt']);
            
            % reassign intensities using mask
            vol_mask = zeros(size(vol));
            for l = select(:)'
                ll = find(sum(select==l,2)); % line number
                % fix for limitation of 'each row to have the same number of values' 
                vx = vol==l;
                if sum(vx) == 0
                    %disp(sprintf('No match for  %g.',l))
                else
                    vol_mask(vx) = ll;
                end
                % patch end
            end
            
            % replace vol with vol_mask
            vol = vol_mask;
            labels = unique(vol);
            labels = setdiff(labels,0);

        case 'DKT'
            vol_fname = fullfile(subjectpath,subjects{s},'mri','aparc.DKTatlas40+aseg.mgz');
            vol = load_mgh(vol_fname);
            labels = unique(vol);
            % only the cortical regions
            labels = labels(labels>999);
            % remove the 'unknown' regions
            labels = setdiff(labels,[ 1000 2000]);

        case 'none'
            vol_fname = fullfile(subjectpath,[subjects{s} '.mgz']);
            vol = load_mgh(vol_fname);
            labels = unique(vol);
            labels = setdiff(labels,0);

        otherwise
            % not sure what to do with that request...
            disp(sprintf('%s is not a valid parcellation scheme',options.aparc));
            failed = 1;
    end
    fprintf('%g region(s).\n',length(labels))
    
    if failed == 0
        for l = 1:length(labels)
            if length(labels) > 1 & mod(l,10)==0
                fprintf('%g...',l)
            end
            
            % box sizes to measure complexity, scaled by powers of 2
            r = options.boxsizes;
            
            % extract portion of vol that is specific label
            vol_label = (vol==labels(l));
            % crop the volume, with padding of half of the largest box size
            vol_label = calcFD_volCrop(vol_label,max(r)/2);
            
            % if not counting filled voxels, need to hollow out the vol
            if options.countFilled == 0
                vol_label = calcFD_hollowVol(vol_label);
            end
            
            switch options.alg
                case 'boxcount'
                    n = calcFD_boxcount(vol_label,r);
                case 'dilate'
                    n = calcFD_dilate(vol_label,r);
            end
            
            if ~isnan(n)
                % linear fit
                c = [log2(r)' ones(length(r),1)] \ -log2(n)';
            else
                % failed
                c(1) = NaN;
                disp('Failed. Check input volume and options.input txt file.')
            end
            fd(s,l) = c(1); % slope
        end
        fprintf('done.\n')
        
        % for debugging
        % save([options.output(1:(end-4))])
    end
end

% error handling
if ~exist('fd')
    disp('No FD values calculated. Please check that ''subjects'' and ''subjectpath'' were specified correctly.');
end

if isfield(options,'output')
    % output FD txt file to working directory
    calcFD_save(options.output,fd,subjects,labels);
end

% delete debug temp file
% delete([options.output(1:(end-4)) '.mat']) 
