function mmi_grid_prep(data_name,roiopt,gridres,tfsopt)
% roiopt = 'g' guassian weighting
% roiopt = 'c' centroid
% roiopt = 's' sensors
% roiopt = 'grid' mni grid
% gridres = grid resolution in mm, for 'g' and 'grid' options 

% addpath /home/liuzzil2/fieldtrip-20190812/
% ft_defaults
% addpath('~/fieldtrip-20190812/fieldtrip_private')
% addpath ~/ppyll1/matlab/svdandpca

%% Co-register MRI from fiducial positions

% LTA model latent variables:
% EC: Expectation of certain value
% EG: Expectation during gabling
% Ediff: Drift rate
% LTA: Long term average with gamma:   1/t * sum_i=1 ^t(V(i)^gamma),   cumsum(LTA.OutcomeAmount^gamma)./(1:ntrials)'
% V_i^gamma = outcome of trial i
% new_p = subjective winning probability
% RPE = Reward prediction error
% LTA_sum  = sum(LTA)
% RPE_sum = sum(RPE)
% log_like
% mood_log_like

sub = data_name(1:5);
data_path = ['/data/MBDU/MEG_MMI3/data/derivatives/sub-',sub,'/'];
cd(data_path)

processing_folder = [data_path,data_name,'/beamforming'];
if ~exist(processing_folder,'dir')
    mkdir(processing_folder)
end


%% Read events

[bv_match,bv] = match_triggers_fc(data_name);

% cue_match = bv_match.answer;
% choice_match = bv_match.choice;
% outcome_match  = bv_match.outcome;
% mood_match = bv_match.ratemood;
% blockmood_match = bv_match.blockmood;
tasktime = bv_match.time;

mood_sample = bv_match.ratemood.sample(bv_match.ratemood.sample~=0);
% mood_sample = cat(2,mood_sample,bv_match.blockmood.sample(bv_match.blockmood.sample~=0));

[mood_sample, moodind] = sort(mood_sample);

mood =  bv_match.ratemood.mood(bv_match.ratemood.sample~=0);
% mood = cat(2,mood,bv_match.blockmood.mood(bv_match.blockmood.sample~=0));

mood = mood(moodind);

trials =  bv_match.ratemood.bv_index(bv_match.ratemood.sample~=0);
% trials = cat(2,trials,bv_match.blockmood.bv_index(bv_match.blockmood.sample~=0)-0.5);

trials = trials(moodind)-12;

% Standard model
A = bv.outcomeAmount; % Outcome
A(isnan(A)) = [];
ntrials = length(A);
% LTA model
EltaH = cumsum(A)./(1:ntrials)'; % Expectation, defined by Hanna
RltaH = A - EltaH; % Assume RPE of first trial is 0

g = 0.8;

E_LTA = zeros(ntrials,1);
RPE = zeros(ntrials,1);
for t = 1:ntrials
    E_LTA(t) = sum( g.^(0:(t-1))' .* EltaH(t:-1:1) );
    RPE(t) = sum( g.^(0:(t-1))' .* RltaH(t:-1:1) );
end

E_LTA = E_LTA(trials);
RPE = RPE(trials);

if strcmp(roiopt,'s')
    
    %% Clean data with ICA
    
    cfg = [];
    cfg.dataset = data_name;
    cfg.continuous = 'yes';
    cfg.channel = 'MEG';
    % cfg.demean = 'yes';
    % cfg.bpfilter = 'yes';
    % cfg.bpfreq = [1 150];
    data = ft_preprocessing(cfg);
    f = data.fsample;
    
    if exist([processing_folder,'/ICA_artifacts.mat'],'file')
        load([processing_folder,'/ICA_artifacts.mat']);
    end
    
    cfg           = [];
    cfg.component = 1:length(comps.label);
    data          = ft_rejectcomponent(cfg, comps,data);
    
    [datave,ttdel]= define_trials(mood_sample, data, tasktime, [0,3],0);
    
    if strcmp(tfsopt,'pwelch')
        TFS = cell(1,length(datave.trial));
        for tt = 1:length(datave.trial)
            ve = datave.trial{tt}';
            [Pxx,F] = pwelch(ve,[],[],[],f);
            TFS{tt} = sum(Pxx,2);
        end
        TFS = cell2mat(TFS);
        figure; plot(F,TFS); xlim([1 50])
    else
        cfg = [];
        cfg.output     = 'pow';
        cfg.channel    = 've';
        cfg.method     = 'mtmconvol';
        cfg.foi        = [1:0.5:4,5:14,16:2:40,45:5:150];
        cfg.t_ftimwin  = 5./cfg.foi;
        cfg.tapsmofrq  = 0.3 *cfg.foi;
        cfg.toi        = 0:0.05:3;
        cfg.keeptrials  = 'yes';
        cfg.pad='nextpow2';
        TFRmult = ft_freqanalysis(cfg, datave);
        
        TFR  = zeros(length(TFRmult.freq),length(datave.trial));
        for ff = 1:length(TFRmult.freq)
            indf = ~isnan(squeeze(TFRmult.powspctrm(1,1,ff,:)));
            TFR(ff,:) = squeeze(mean(TFRmult.powspctrm(:,1,ff,indf),4));
        end
        
        %         figure; plot(TFRmult.freq,TFR)
        TFS{ii} = TFR;
    end
    
    
    save_name = ['/data/MBDU/MEG_MMI3/results/mmiTrial_aal_prep_mu5max/pre_mood/',sub];
    
    n = str2double(data_name(end-3));
    if ~isnan(n) %check for number at end of filename
        save_name = [save_name,'_',data_name(end-3)];
    else
        save_name = [save_name,'_1'];
    end
    
    
    mood(ttdel) = [];
    trials(ttdel) = [];
    S = repmat(sub,length(mood),1);
    
    ltvmood = table(S,trials',mood','VariableNames',...
        {'subject','trial','mood'});
    save(save_name,'ltvmood','TFSp','F','-append');
    
else
    %% Co-register MRI
    
    mri_name = [sub,'_anat+orig.BRIK'];
    
    if ~exist(mri_name,'file')
        unix(['gunzip ',mri_name])
    end
    
    mri = ft_read_mri(mri_name,'dataformat','afni_brik');
    
    tagset_shape = mri.hdr.TAGSET_NUM;
    tagset_coord = mri.hdr.TAGSET_FLOATS;
    tagset_coord = reshape(tagset_coord,fliplr(tagset_shape)); % nas, lpa, rpa
    
    tagset_p = zeros(1,3);  % Ideal orientation {RL; PA; IS}
    for ii =1:3
        if strcmp(mri.hdr.Orientation(ii,:),'AP') || strcmp(mri.hdr.Orientation(ii,:),'PA')
            tagset_p(ii) = 2;
        elseif strcmp(mri.hdr.Orientation(ii,:),'LR') || strcmp(mri.hdr.Orientation(ii,:),'RL')
            tagset_p(ii) = 1;
        elseif strcmp(mri.hdr.Orientation(ii,:),'SI') || strcmp(mri.hdr.Orientation(ii,:),'IS')
            tagset_p(ii) = 3;
        end
    end
    
    m = [   -1  0   0   mri.dim(1)
        0   -1  0   mri.dim(2)
        0   0   1   1
        0   0   0   1] ;
    
    
    tagset_coord = tagset_coord(tagset_p,:)'; % fiducials have shuffled coordinates
    
    mri.transform(1:3,4) = mri.hdr.ORIGIN; % change translation to origin
    
    mri.transform = mri.transform/m;
    fiducial_coord = (mri.transform \[tagset_coord,ones(3,1)]')';
    
    cfg = [];
    cfg.method = 'fiducial';
    cfg.fiducial.nas    = fiducial_coord(1,1:3); %position of nasion
    cfg.fiducial.lpa    = fiducial_coord(2,1:3); %position of LPA
    cfg.fiducial.rpa    = fiducial_coord(3,1:3); %position of RPA
    cfg.coordsys = 'ctf';
    cfg.viewresult = 'no';
    
    mri = ft_volumerealign(cfg,mri);
    
    if ~exist([sub,'_coreg.nii'],'file')
        writebrik([sub,'_coreg'],mri);
    end
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% Segment MRI
    if ~exist([processing_folder,'/headmodel.mat'],'file')
        cfg = [];
        cfg.output  = 'brain';
        segmentmri = ft_volumesegment(cfg,mri);
        
        % Head model
        
        cfg = [];
        cfg.method = 'singleshell';
        vol = ft_prepare_headmodel(cfg, segmentmri);
        
        save([processing_folder,'/headmodel.mat'],'vol')
    else
        load([processing_folder,'/headmodel.mat']);
    end
    sens = ft_read_sens(data_name,'senstype','meg');
    
    
    %% AAL atlas
%     gridres = 5; % resolution of beamformer grid in mm
    
    % Load fieldtrip 10mm MNI grid
    ftpath   = '/home/liuzzil2/fieldtrip-20190812/';
    load(fullfile(ftpath, ['template/sourcemodel/standard_sourcemodel3d',num2str(gridres),'mm']));
    template_grid = sourcemodel;
    atlas = ft_read_atlas('~/fieldtrip-20190812/template/atlas/aal/ROI_MNI_V4.nii');
    atlas = ft_convert_units(atlas,sourcemodel.unit);
    
    cfg = [];
    cfg.interpmethod = 'nearest';
    cfg.parameter = 'tissue';
    sourcemodelAAL = ft_sourceinterpolate(cfg, atlas, sourcemodel);
    
    clear sourcemodel
    
    %% Sourcemodel warp MNI grid
    
    % sourcemodel based on 5mm grid MNI brain
    cfg = [];
    cfg.mri = mri;
    cfg.warpmni = 'yes';
    cfg.template  = template_grid; % Has to be template grid! Made from ft_prepare_sourcemodel
    cfg.unit      = 'm';
    cfg.nonlinear = 'yes';
    sourcemodel = ft_prepare_sourcemodel(cfg);
    locs = sourcemodel.pos;
    if  ~strcmp(roiopt,'grid')
        %% Find location of AAL ROIs
        R = length(sourcemodelAAL.tissuelabel);
        locs = zeros(R,3);
        locsAAL = cell(R,1);
        for ii = 1:R
            ind = find(sourcemodelAAL.tissue == ii);
            voxc = mean(sourcemodel.pos(ind,:)); % centroid
            locs(ii,:) = voxc;

            locsAAL{ii} = sourcemodel.pos(ind,:);

        end

        if strcmp(roiopt,'g')
            locsc = locs;
            locs = cell2mat(locsAAL);
        end
    end
    %% Calculate lead fields
    
    cfg                 = [];
    cfg.grad            = sens;
    cfg.headmodel       = vol;
    cfg.reducerank      = 2;
    cfg.channel         = {'MEG'};
    cfg.sourcemodel.pos = locs; %sourcemodel.pos
    cfg.sourcemodel.unit   = 'm';
    cfg.siunits         = true;
    cfg.normalize = 'no'; % To normalize power estimate (center of the head bias for beamformer and superficial bias for mne)
    [grid] = ft_prepare_leadfield(cfg);
    
    %% Clean data with ICA
    
    cfg = [];
    cfg.dataset = data_name;
    cfg.continuous = 'yes';
    cfg.channel = 'MEG';
    % cfg.demean = 'yes';
    % cfg.bpfilter = 'yes';
    % cfg.bpfreq = [1 150];
    data = ft_preprocessing(cfg);
    f = data.fsample;
    
    if exist([processing_folder,'/ICA_artifacts.mat'],'file')
        load([processing_folder,'/ICA_artifacts.mat']);
        
    end
    
    cfg           = [];
    cfg.component = 1:length(comps.label);
    data          = ft_rejectcomponent(cfg, comps,data);
    
    %%
    filt_order = []; % default
    
    data_filt = ft_preproc_bandpassfilter(data.trial{1}, data.fsample,[1 150],filt_order,'but');
    
    data.trial{1} = data_filt;
    clear data_filt
       
    
    %% Beamfomer
    icacomps = length(data.cfg.component);
    
    C = cov(data.trial{1}');
    E = svd(C);
    nchans = length(data.label);
    noiseC = eye(nchans)*E(end-icacomps); % ICA eliminates from 2 to 4 components
    
    % Cr = C + 4*noiseC; % old normalization
    Cr = C + 0.05*eye(nchans)*E(1); % 5% max singular value
    
    
    if strcmp(roiopt,'g')
        VE = cell(R,1);
        n =0;
        for r = 1:R
            clc
            fprintf('SAM running %d/%d .\n', r,R)
            
            L = grid.leadfield( n + (1:size(locsAAL{r},1)) );
            
            VEr = zeros(data.sampleinfo(2),size(locsAAL{r},1));
            
            voxc = locsc(r,:); % centroid
            GD = zeros(1,size(locsAAL{r},1));
            for ii = 1:length(L)
                
                d = sqrt(sum((grid.pos(n+ii,:)-voxc).^2,2)); % distance from centroid
                GD(ii) = exp(-(d.^2)/1e-4); % gaussian weigthing
                lf = L{ii}; % Unit 1Am
                if GD(ii) > 0.05 && ~isempty(lf) % include voxels with weighting > 5%
                    % %  G O'Neill method, equivalent to ft
                    [v,d] = svd(lf'/Cr*lf);
                    d = diag(d);
                    jj = 2;
                    
                    lfo = lf*v(:,jj); % Lead field with selected orientation
                    
                    w = Cr\lfo / sqrt(lfo'/(Cr^2)*lfo) ;
                    
                    VEr(:,ii)  = GD(ii)*w'*data.trial{1};
                    
                end
            end
            
            sf = corr(VEr); % check sign
            [~,ind] = max(GD);
            sf= sign(sf(ind,:));
            sf(isnan(sf)) = 0;
            VEr = VEr.*sf;
            VE{r} = sum(VEr,2);
            n = n + size(locsAAL{r},1);
        end
        
    else
        L = grid.leadfield(grid.inside);
        
        %     VE(1:size(L,2)) = {0};
        %     W(1:size(L,2)) = {0};
        clear cfg
        TFS = cell(size(L));
        TFSp = cell(size(L));
        for ii = 1:length(L)
            lf = L{ii}; % Unit 1Am
            
            % %  G O'Neill method, equivalent to ft
            [v,d] = svd(lf'/Cr*lf);
            d = diag(d);
            jj = 2;
            
            lfo = lf*v(:,jj); % Lead field with selected orientation
            
            w = Cr\lfo / sqrt(lfo'/(Cr^2)*lfo) ;
            %         W{ii} = w;
            %         VE  = w'*data.trial{1};
            
            datave = struct;
            datave.time = data.time;
            datave.fsample = data.fsample;
            datave.sampleinfo = data.sampleinfo;
            datave.label = {'ve'};
            datave.trial{1} =  w'*data.trial{1};
            [datave,ttdel]= define_trials(mood_sample, datave, tasktime, [0,3],0);
            
            if strcmp(tfsopt,'pwelch')
                ve = cell2mat(datave.trial')';
                [Pxx,F] = pwelch(ve,[],[],[],f);
                TFSp{ii} = Pxx(F>1 & F<=150,:);
                F = F(F>=1 & F<=150);
                
                %         figure; plot(F,Pxx)
            else
                cfg = [];
                cfg.output     = 'pow';
                cfg.channel    = 've';
                cfg.method     = 'mtmconvol';
                cfg.foi        = [1:0.5:4,5:14,16:2:40,45:5:150];
                cfg.t_ftimwin  = 5./cfg.foi;
                cfg.tapsmofrq  = 0.3 *cfg.foi;
                cfg.toi        = 0:0.05:3;
                cfg.keeptrials  = 'yes';
                cfg.pad='nextpow2';
                TFRmult = ft_freqanalysis(cfg, datave);
                
                TFR  = zeros(length(TFRmult.freq),length(datave.trial));
                for ff = 1:length(TFRmult.freq)
                    indf = ~isnan(squeeze(TFRmult.powspctrm(1,1,ff,:)));
                    TFR(ff,:) = squeeze(mean(TFRmult.powspctrm(:,1,ff,indf),4));
                end
                
                %         figure; plot(TFRmult.freq,TFR)
                TFS{ii} = TFR;
            end
            clc
            fprintf('SAM running %.1f .\n', ii/length(L)*100)
            
        end
    end
    %
    % ii = 76;
    % pcolor(TFRmult.freq,1:32,TFS{ii}');  shading interp;
    % xlabel('frequency (Hz)'); ylabel('mood'); colorbar
    %%
    
    save_name = ['/data/MBDU/MEG_MMI3/results/mmiTrial_aal_prep_mu5max/pre_mood/',sub];
    
    n = str2double(data_name(end-3));
    if ~isnan(n) %check for number at end of filename
        save_name = [save_name,'_',data_name(end-3)];
    else
        save_name = [save_name,'_1'];
    end
    
    
    mood(ttdel) = [];
    trials(ttdel) = [];
    S = repmat(sub,length(mood),1);
    RPE(ttdel) = [];
    E_LTA(ttdel) = [];
    ltvmood = table(S,trials',mood',RPE,E_LTA,'VariableNames',...
        {'subject','trial','mood','RPE','E'});
    
    %%
    
    if strcmp(tfsopt,'pwelch')
        save(save_name,'ltvmood','TFSp','F','-append');
    else
        freqs = TFRmult.freq;
        save(save_name,'ltvmood','TFS','freqs','-append');
    end
end



