% stick all the parameters in an array
% (Note that they are strings)
clear all
close all
clc
%% Compile script
cd ~/matlab/matlab_compiler_test

filename = 'mmi_LTA_trials_abs';
% unix(['cp ~/matlab/',filename,'.m ~/matlab/matlab_compiler_test/.'])
eval(sprintf('mcc2 -v -m %s.m -R -nojvm singleCompThread ',filename))

%% Set up parameters
nrois = 116;
% nrois = 269;
param_list = cell(nrois,1);
for nn = 1:nrois
    n = num2str(nn);
    if size(n,2) == 1
        n = ['00',n];
    elseif size(n,2) == 2
        n = ['0',n];
    end
    param_list{nn} = n;
end

%%

% freq = 'beta';
freq  = 'evoked_outcome';
       
if regexp(freq,'outcome')
    npoints = '360';
elseif regexp(freq,'choice')
    npoints = '390';
end

meg_data_name = ['meg_trials_',freq,'.txt'];
latent_vars_name = ['latent_vars_',freq,'.csv'];

data_path = '/data/MBDU/MEG_MMI3/results/mmiTrial_aal_prep_mu5max/latent_vars_new/';
% data_path = '/data/MBDU/MEG_MMI3/results/mmiTrial_sensors_prep/';

opts = detectImportOptions([data_path,latent_vars_name]);
X = readtable([data_path,latent_vars_name],opts);

fit_parameters = X.Properties.VariableNames(3:end);
fit_parameters = {'RPE'};

runcompiled = ['run_',filename,'.sh'];               
compv = 'v96'; % compiler version

cd ~/matlab/matlab_compiler_test
command_list = cell(1,length(param_list)*length(fit_parameters));

jj = 0;
% make a command on a new line for each parameter
for m = 1:length(fit_parameters)
    fit_parameter = fit_parameters{m};
    for ii = 1:length(param_list)
        jj = jj+1;
        command_list{jj} =  sprintf(['export MCR_CACHE_ROOT=/lscratch/$SLURM_JOB_ID;'...
            '  cd /lscratch/$SLURM_JOBID; if [ -f "%s"] ;  then  echo "data already in lscratch"; ',...
            '  else cp %s%s /lscratch/$SLURM_JOB_ID/ && cp %s%s /lscratch/$SLURM_JOB_ID/; fi ;'...
            ' test -d /lscratch/$SLURM_JOB_ID/v96 || tar -C /lscratch/$SLURM_JOB_ID -xf /usr/local/matlab-compiler/v96.tar.gz '...
            ' && ~/matlab/matlab_compiler_test/%s '...
            ' /lscratch/$SLURM_JOB_ID/v96 %s %s %s %s %s %s %s\n'],...
            meg_data_name,data_path,meg_data_name,data_path,latent_vars_name,runcompiled,...
            meg_data_name,latent_vars_name,param_list{ii},npoints,fit_parameter,freq,data_path);
    end
end
command_list(jj+1:end) = [];
command_list = cell2mat(command_list);
% write the commands into a swarm file
file_handle = fopen(sprintf('mmi_LTA_trials_%s.swarm',freq),'w+');
% file_handle = fopen(sprintf('mmi_LTA_trials_%s_missing.swarm',freq),'w+');

fprintf(file_handle,command_list);
fclose(file_handle);

%     jobid = evalc(sprintf('!swarm --job-name mmiMEGlmix_%s -g 4 --time 01:00:00 -f mmi_LTA_trials_%s.swarm --devel',fit_parameter,fit_parameter))


% Try 1 instance of compiled script
% eval(sprintf('!./%s /usr/local/matlab-compiler/v96 %s %s %s %s %s',runcompiled,meg_data_name,latent_vars_name,'002',npoints,fit_parameter))

%% Run swarm
clc
if ~exist(sprintf('%s/%s',data_path,freq),'dir')
    mkdir(sprintf('%s/%s',data_path,freq))
end
cd ~/matlab/matlab_compiler_test

emailnote = '"--mail-type=FAIL,END"';
% need to include lscratch! see matlab biowulf page
mem = '1';  % gigabytes
threads = '2'; % number of threads
bundles = '7'; % limits number of jobs running at the same time
logfolder = '~/matlab/matlab_compiler_test/swarm_logs';

jobid = evalc(sprintf('!swarm --job-name lmix%s --gres lscratch:10 -g %s -t %s -b %s --time 0:30:00 --logdir %s -f mmi_LTA_trials_%s.swarm --sbatch %s --devel',...
    freq,mem,threads,bundles, logfolder,freq,emailnote))

% try starting swarm from a non interactive session
fprintf('swarm --job-name lmix%s --gres lscratch:10 -g %s -t %s -b %s --time 30:00:00 --logdir %s -f mmi_LTA_trials_%s.swarm --sbatch %s\n',...
    freq,mem,threads,bundles, logfolder,freq,emailnote);
