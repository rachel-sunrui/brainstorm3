function bst_startup(BrainstormHomeDir, isGUI, isServer, BrainstormDbDir)
% BST_STARTUP: Start a new Brainstorm Session.
%
% USAGE:  bst_startup(BrainstormHomeDir, isGUI=1, isServer=0, BrainstormDbDir=[])

% @=============================================================================
% This function is part of the Brainstorm software:
% http://neuroimage.usc.edu/brainstorm
% 
% Copyright (c)2000-2017 University of Southern California & McGill University
% This software is distributed under the terms of the GNU General Public License
% as published by the Free Software Foundation. Further details on the GPLv3
% license can be found at http://www.gnu.org/copyleft/gpl.html.
% 
% FOR RESEARCH PURPOSES ONLY. THE SOFTWARE IS PROVIDED "AS IS," AND THE
% UNIVERSITY OF SOUTHERN CALIFORNIA AND ITS COLLABORATORS DO NOT MAKE ANY
% WARRANTY, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF
% MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, NOR DO THEY ASSUME ANY
% LIABILITY OR RESPONSIBILITY FOR THE USE OF THIS SOFTWARE.
%
% For more information type "brainstorm license" at command prompt.
% =============================================================================@
%
% Authors: Sylvain Baillet, John C. Mosher, 1999
%          Francois Tadel, 2008-2015


%% ===== MATLAB CHECK =====
% Parse inputs
if (nargin < 4) || isempty(BrainstormDbDir)
    BrainstormDbDir = [];
end
% If version is too old
MatlabVersion = bst_get('MatlabVersion');
if (MatlabVersion < 701)
    error('Brainstorm needs a version of Matlab >= 7.1');
end
% Is Matlab running (if not it is a compiled version)
isMatlabRunning = ~(exist('isdeployed', 'builtin') && isdeployed);
% Compiled version: Force system look and feel
if ~isMatlabRunning
    try
        javax.swing.UIManager.setLookAndFeel(javax.swing.UIManager.getSystemLookAndFeelClassName());
    catch
        % Whatever....
    end
end

% Startup message
disp(' ');
disp('BST> Starting Brainstorm:');
disp('BST> =================================');


%% ===== BRAINSTORM VERIFICATIONS =====
% Check that no interface is already running
if isappdata(0, 'BrainstormRunning')
    disp('BST> Brainstorm is already running. Restarting...');
    bst_exit();
end
% Initialize shared structure
global GlobalData;
GlobalData = db_template('GlobalData');
GlobalData.Program.isGUI    = isGUI;
GlobalData.Program.isServer = isServer;
GlobalData.DataBase.LastSavedTime = tic();   % Save the current time, to know when to save the database
% Save the software home directory
bst_set('BrainstormHomeDir', BrainstormHomeDir);
% Splash screen
bst_splash('show');

% === BRAINSTORM VERSION ===
try
    % Read "version.txt"
    fid = fopen(bst_fullfile(BrainstormHomeDir, 'doc', 'version.txt'),'rt');
    Name = fgetl(fid); % the name line
    STR2 = fgetl(fid); % the second line with version, release and date
    % Format should be "Version 2.0 (R14) 27-June-2005" in that order.
    %  We will read last three items as Version, Release, and Date
    fclose(fid);
    Name = Name(3:end); %trim the comment
    STR2 = fliplr(STR2); % easier handling if read backwards
    [Date,STR2] = strtok(STR2);
    [Release,STR2] = strtok(STR2);
    Version = strtok(STR2);
    % reverse them to original
    Version = fliplr(Version);
    Release = fliplr(Release);
    Date = fliplr(Date); 
    Date = strrep(Date, '(', '');
    Date = strrep(Date, ')', '');
catch
    Name = 'Brainstorm';
    Version = '?';
    Release = '?';
    Date    = '?';
end
% Save version in matlab preferences
bstVersion = struct('Name',    Name, ...
                    'Version', Version, ...
                    'Release', Release, ...
                    'Date',    Date);
bst_set('Version', bstVersion);
% Display version number
disp(['BST> Version: ' Date ]);
% Get release date
localRel.year  = str2num(Release(1:2));
localRel.month = str2num(Release(3:4));
localRel.day   = str2num(Release(5:6));


%% ===== FORCE COMPILATION OF SOME INTERFACE FILES =====
disp('BST> Compiling main interface files...');
tree_callbacks();
bst_figures();
figure_topo();
figure_3d();
figure_mri();
figure_timeseries();
figure_timefreq();
bst_colormaps();
bst_memory();
bst_navigator();


%% ===== EMPTY TEMPORARY DIRECTORY =====
gui_brainstorm('EmptyTempFolder');


%% ===== EMPTY REPORTS DIRECTORY =====
% Get temporary directory
reportsDir = bst_get('UserReportsDir');
% If directory exists
if isdir(reportsDir)
    disp('BST> Deleting old process reports...');
    % List contents of folder
    listDir = dir(bst_fullfile(reportsDir, 'report_*.mat'));
    % If there are files in this folder (older versions of Matlab do not have this datenum field)
    if ~isempty(listDir) && isfield(listDir, 'datenum')   
        % Get files that are older than 15 days
        iOldFiles = find(now() - [listDir.datenum] > 15);
        % Delete contents of directory
        for iFile = 1:length(iOldFiles)
            file_delete(bst_fullfile(reportsDir, listDir(iOldFiles(iFile)).name), 1);
        end
    end
end


%% ===== LOAD CONFIG FILE =====
disp('BST> Loading configuration file...');
% Get user database file : brainstorm.mat
dbFile = bst_get('BrainstormDbFile');
% Current DB version
CurrentDbVersion = 4;
% Get default colormaps list
sDefColormaps = bst_colormaps('Initialize');
isDbLoaded = 0;
% If file exists: load it
if file_exist(dbFile)
    % Load database file
    try
        bstOptions = load(dbFile);
    catch
        bst_splash('hide');
        java_dialog('msgbox', [...
            'Error: The database file was not saved properly.' 10 10 ...
            'Possible reason: Your hard drive is full or your quota exceeded.' 10 ...
            'Your user options are lost, but your database is probably safe:' 10 ...
            ' - Try to delete files in your home folder' 10 ...
            ' - Change the temporary folder in the Brainstorm preferences' 10 ...
            ' - Import again your database folder (File > Import database).'], 'Database error');
        bstOptions = [];
    end
else
    bstOptions = [];
end
% Copy saved preferences to current instance
if ~isempty(bstOptions)
    % Add its contents in root app data
    if isfield(bstOptions, 'iProtocol')
        GlobalData.DataBase.iProtocol          = bstOptions.iProtocol;
        GlobalData.DataBase.ProtocolInfo       = bstOptions.ProtocolsListInfo;
        GlobalData.DataBase.ProtocolSubjects   = bstOptions.ProtocolsListSubjects;
        GlobalData.DataBase.ProtocolStudies    = bstOptions.ProtocolsListStudies;
        GlobalData.DataBase.BrainstormDbDir    = bstOptions.BrainStormDbDir;
        GlobalData.DataBase.isProtocolModified = zeros(1, length(bstOptions.ProtocolsListInfo));
        if isfield(bstOptions, 'DbVersion') && ~isempty(bstOptions.DbVersion)
            GlobalData.DataBase.DbVersion = bstOptions.DbVersion;
        end
        if isfield(bstOptions, 'isProtocolLoaded') && ~isempty(bstOptions.isProtocolLoaded)
            GlobalData.DataBase.isProtocolLoaded = bstOptions.isProtocolLoaded;
        else
            GlobalData.DataBase.isProtocolLoaded = ones(1, length(bstOptions.ProtocolsListInfo));
        end
        isDbLoaded = 1;
    end
    % Get saved colormaps
    if isfield(bstOptions, 'Colormaps') && isstruct(bstOptions.Colormaps)
        fNames = fieldnames(sDefColormaps);
        if (length(fieldnames(bstOptions.Colormaps)) ~= length(fNames)) || ~isequal(fieldnames(bstOptions.Colormaps.(fNames{1})), fieldnames(sDefColormaps.(fNames{1})))
            disp('BST> Colormap structure was updated. Fixing...');
        else
            GlobalData.Colormaps = bstOptions.Colormaps;
        end
    end
    % Clone control
    if isfield(bstOptions, 'CloneLock') && ~isempty(bstOptions.CloneLock)
        GlobalData.Program.CloneLock = bstOptions.CloneLock;
    end
    % Get saved preferences
    if isfield(bstOptions, 'Preferences') && isstruct(bstOptions.Preferences)
        GlobalData.Preferences = struct_copy_fields(GlobalData.Preferences, bstOptions.Preferences, 0);
    end
    % Get saved montages
    if isfield(bstOptions, 'ChannelMontages') && isstruct(bstOptions.ChannelMontages) && ...
            all(isfield(bstOptions.ChannelMontages, fieldnames(GlobalData.ChannelMontages))) && ...
            (length(bstOptions.ChannelMontages.Montages) > 20)
        GlobalData.ChannelMontages = bstOptions.ChannelMontages;
        % Reset butterfly plot selection
        panel_montage('SetCurrentMontage', 'MEG', []);
    end
    % Get saved process pipelines
    if isfield(bstOptions, 'Pipelines') && isstruct(bstOptions.Pipelines) && ...
            all(isfield(bstOptions.Pipelines, {'Name', 'Processes'}))
       GlobalData.Processes.Pipelines = bstOptions.Pipelines;
    end
    % Reset current search filter
    if isfield(GlobalData.Preferences, 'NodelistOptions') && isfield(GlobalData.Preferences.NodelistOptions, 'String') && ~isempty(GlobalData.Preferences.NodelistOptions.String)
        GlobalData.Preferences.NodelistOptions.String = '';
    end
    % Check database structure for updates 
    db_update(CurrentDbVersion);
else
    % Database version is not defined, so it up-to-date
    GlobalData.DataBase.DbVersion = CurrentDbVersion;
end
% Check that Colormaps are defined
if isempty(GlobalData.Colormaps)
    GlobalData.Colormaps = sDefColormaps;
end
% Check that default montages are loaded
if (length(GlobalData.ChannelMontages.Montages) < 5) || ~ismember('CTF LF', {GlobalData.ChannelMontages.Montages.Name}) || ~ismember('Bad channels', {GlobalData.ChannelMontages.Montages.Name})
    disp('BST> Loading default montages...');
    % Reset list of montages
    GlobalData.ChannelMontages.Montages = [];
    % Load default selections
    panel_montage('LoadDefaultMontages');
end


%% ===== AUTOMATIC UPDATES =====
% Automatic updates disabled: do not check for internet connection
if ~bst_get('AutoUpdates')
    disp('BST> Warning: Automatic updates are disabled.');
    disp('BST> Warning: Make sure your version of Brainstorm is up to date.');
% Matlab is running: check for updates
elseif isMatlabRunning && isGUI
    % Check internect connection
    fprintf(1, 'BST> Checking internet connectivity... ');
    [isInternet, onlineRel] = bst_check_internet();
    % If no internet connection
    if ~isInternet
        disp('failed');
        disp('BST> Could not check for Brainstorm updates.')
    else
        disp('ok');
        % Determine if release is old (local version > 30 days older than online version)
        daysOnline = onlineRel.year*365 + onlineRel.month*30 + onlineRel.day;
        daysLocal  =  localRel.year*365 +  localRel.month*30 +  localRel.day;
        isOld = ((daysOnline - daysLocal) > 30);
        % Display online version number
        if ((daysOnline - daysLocal) > 1)
            strOnline = datestr([2000+onlineRel.year, onlineRel.month, onlineRel.day, 0, 0, 0]);
            disp(['BST> Update available online: ' strOnline '']);
        end
        % Checking version: download if more then one month old
        if isOld 
            disp('BST> Your version of brainstorm is old. Update is required.');
            % Check access rights
            if ~file_attrib(bst_fileparts(BrainstormHomeDir, 1), 'w') || ~file_attrib(BrainstormHomeDir, 'w')
                disp('BST> Brainstorm installation folder is read-only. Cannot update...');
            else
                % Hide splash screen
                bst_splash('hide');
                % Update brainstorm
                isUpdated = bst_update(1);
                % If update successful: Matlab or Brainstorm restart
                if isUpdated
                    return
                end
            end
        end
    end
end


%% ===== START BRAINSTORM GUI =====
disp('BST> Initializing user interface...');
% Get screen configuration
GlobalData.Program.ScreenDef = gui_layout('GetScreenClientArea');
% Create main window
gui_initialize();
% Abort if something went wrong
if isempty(GlobalData.Program.GUI)
    return;
end


%% ===== INITIALIZE DATABASE =====
if ~isDbLoaded
    % Initialize structures
    GlobalData.DataBase.iProtocol          = 0;
    GlobalData.DataBase.ProtocolInfo       = repmat(db_template('ProtocolInfo'), 0);
    GlobalData.DataBase.ProtocolSubjects   = repmat(db_template('ProtocolSubjects'), 0);
    GlobalData.DataBase.ProtocolStudies    = repmat(db_template('ProtocolStudies'), 0);
    GlobalData.DataBase.isProtocolLoaded   = [];
    GlobalData.DataBase.isProtocolModified = [];
end


%% ===== CHECK FOR EEGLAB INSTALL =====
fminPath = lower(which('fminsearch'));
if ~isempty(strfind(fminPath, 'eeglab'))
    strProg = 'EEGLAB';
elseif ~isempty(strfind(fminPath, 'spm'))
    strProg = 'SPM';
elseif ~isempty(strfind(fminPath, 'fieldtrip'))
    strProg = 'FieldTrip';
else
    strProg = [];
end
if ~isempty(strProg)
    if ~isGUI
        disp(['BST> Warning: Some ' strProg ' functions shadow Matlab''s standard functions.']);
        disp(['BST> Warning: Please remove ' strProg ' from your Matlab path.']);
    else
        bst_splash('hide');
        java_dialog('warning', [strProg ' is installed on your system and shadows some standard Matlab functions.' 10 ...
                                'Without access to the function fminsearch, Brainstorm will not run properly.' 10 10 ...
                                'Please remove ' strProg ' from your Matlab path and restart Brainstorm.']);
    end
end


%% ===== START OPENGL =====
fprintf(1, 'BST> Starting OpenGL engine... ');
[isOpenGL, DisableOpenGL] = panel_options('StartOpenGL');
% If OpenGL cannot be used: display a warning message
if ~isOpenGL
    disp('BST> Warning: No OpenGL support available for this computer.');
    disp('BST>          Display will be slow and ugly.');
% If OpenGL is manually disabled
elseif isOpenGL && (DisableOpenGL == 1)
    disp('BST> Warning: ');
    disp('BST>    * Using this option causes the display to be slow and ugly.');
    disp('BST>    * Select only if you are experiencing serious display bugs with ');
    disp('BST>    * the full hardware acceleration. To edit this option: ');
    disp('BST>    * Menu: File > Set preferences... > Disable OpenGL rendering.');
end


%% ===== PARSE PROCESS FOLDER =====
% Parse process folder
disp('BST> Reading plugins folder...');
panel_process_select('ParseProcessFolder', 1);


%% ===== LICENSE AGREEMENT =====
if isGUI
    % Number of days to allow as grace period for renewing license
    GRACE = 15; 
    % Get previous agreement date (default: current date)
    if isfield(GlobalData, 'Preferences') && isfield(GlobalData.Preferences, 'DateofAgreement') && ~isempty(GlobalData.Preferences.DateofAgreement)
        DateofAgreement = GlobalData.Preferences.DateofAgreement;
    else
        DateofAgreement = datestr(floor(now) - GRACE - 1);
    end
    % Get number of days since last agreement
    DaysSinceAgree = etime(datevec(now),datevec(DateofAgreement));
    DaysSinceAgree = DaysSinceAgree/(60*60*24); % convert seconds to days

    % If user did not agree to Brainstorm license rencently
    if (DaysSinceAgree >= GRACE)
        % Hide splash screen
        bst_splash('hide');
        % Show license agreement panel
        isOk = bst_license();
        % If user did not agree: exit
        if ~isOk
            clear all
            disp('BST> License agreement unsatisfied. Closing Brainstorm...');
            disp('BST> Type ''brainstorm'' to restart Brainstorm.');
            % Release Brainstorm global mutex
            bst_mutex('release', 'Brainstorm');
            return;
        % Else accept validation for 15 days
        else
            disp('BST> License accepted.');
            GlobalData.Preferences.DateofAgreement = datestr(floor(now));
        end
    end
end


%% ===== TEST MEMORY =====
if ispc && (MatlabVersion >= 706)
    try
        % Get Matlab memory
        usermem = memory();
        % Minimum: 1Gb RAM contiguous
        maxsize = round(usermem.MaxPossibleArrayBytes / 1024 / 1024);
        if (maxsize < 1024)
            disp(sprintf('BST> Warning: Maximum variable size: %d Mb', maxsize));
            if isGUI && ~bst_get('IgnoreMemoryWarnings')
                % Hide splash screen
                bst_splash('hide');
                % Display warning
                java_dialog('msgbox', ...
                    ['Your system reports to be short on memory.' 10 10 ...
                     'The maximum block of memory that Matlab can allocate is: ' num2str(maxsize) ' Mb.' 10 ...
                     'The recommended minimum for running Brainstorm is 1024 Mb.' 10 ...
                     'Below this limit, you may experiment a lot of "out of memory" errors.' 10 10 ...
                     'Close all the other applications running on this computer to free some memory.' 10 ...
                     'To ignore this message permanently: File > Preferences > Ignore memory warnings.'], ...
                    'Memory warning');
            end
        end
    catch
        % Whatever...
    end
end


%% ===== SET DATABASE DIRECTORY =====
isImportDb = 0;
% Get database folder
if isempty(BrainstormDbDir)
    BrainstormDbDir = bst_get('BrainstormDbDir');
end
% If folder is not defined yet: ask user to set it
if isempty(BrainstormDbDir)
    % Hide splash screen
    bst_splash('hide');
    % Display message: first startup
    java_dialog('msgbox', ['It is the first time you run Brainstorm on this Matlab installation.' 10 10 ...
                           'First of all, you need to create a new directory to store the Brainstorm database,' 10 ...
                           'called for instance "brainstorm_db".' 10 10 ...
                           'IMPORTANT NOTES: ' 10 ...
                           '- Do not create this database directory in the Brainstorm program directory' 10 ...
                           '- The database directory must contain only files created by Brainstorm.' 10 ...
                           '- Do not put your original data files and personal results in the database directory.' 10 ...
                           '- Do not put any file in the Brainstorm program directory.'], 'Brainstorm setup');
    % Set database folder
    BrainstormDbDir = gui_brainstorm('SetDatabaseFolder');
    % If no directory selected : exit
    if isempty(BrainstormDbDir)
        % Release Brainstorm global mutex
        bst_mutex('release', 'Brainstorm');
        return
    end
    % Check if there are protocols in this folder
    if ~isempty(file_find(BrainstormDbDir, 'brainstormsubject*.mat', 4))
        % Ask if user wants to import all the database
        isImportDb = java_dialog('confirm', ['This folder already contains Brainstorm protocols.' 10 10 ...
                                             'Load all these protocols now ?' 10 10]);
    end
end


%% ===== INITIALIZATION DONE =====
disp('BST> Loading current protocol...');
% Get handle to the main window
jFrame = bst_get('BstFrame');
% If the GUI is requested by the user
if isGUI
    % Show main Brainstorm window
    jFrame.setVisible(1);
    % Weird thing with some macs: by default, window is "always on top"
    if strncmp(computer,'MAC',3)
        jFrame.setVisible(0);
        jFrame.setAlwaysOnTop(0);
        jFrame.setVisible(1);
    end
end
% Display Brainstorm version
jFrame.setTitle(['Brainstorm ' Date]);
% Read the protocols list in UserDataBase
gui_brainstorm('UpdateProtocolsList');
% Load the selected protocol
gui_brainstorm('SetCurrentProtocol', GlobalData.DataBase.iProtocol);
% Update permanent panels (to disable them)
panel_surface('UpdatePanel');
panel_scout('UpdatePanel');
panel_cluster('UpdatePanel');
disp('BST> =================================');
disp(' ');
% Set a flag to mark that brainstorm is now running
setappdata(0, 'BrainstormRunning', 1);
% Hide spash screen
bst_splash('hide');
% Make sure that figure named "Brainstorm" is hidden
hMutex = bst_mutex('get', 'Brainstorm');
set(hMutex, 'Visible', 'off');


%% ===== RELOAD ALL DATABASE =====
% Create file to indicate that Brainstorm was started
StartFile = bst_fullfile(bst_get('BrainstormUserDir'), 'is_started.txt');
% If import database was mandatory
if isImportDb
    disp('BST> Reloading database...');
    db_import(BrainstormDbDir);
% Check if the program was closed unexpectedly
elseif file_exist(StartFile)
    % Delete this file
    if (file_delete(StartFile, 1) == 1) && ~file_exist(StartFile)
        isReloadCurrent = java_dialog('confirm', ...
            ['Brainstorm was not closed properly, some modifications to the current' 10 ...
             'protocol might not have been saved properly in the dabase.' 10 10 ...
             'Reload the current protocol ?' 10 10]);
        if isReloadCurrent
            db_reload_database(GlobalData.DataBase.iProtocol);
        end
    else
        disp('BST> Warning: Brainstorm is already running from a different Matlab session.');
    end
end
% Open a new file to track if Brainstorm is opened
fid = fopen(StartFile, 'w');
fwrite(fid, ['Brainstorm started: ' datestr(now) 10]);
fwrite(fid, ['User: ' char(java.lang.System.getProperty('user.name')) 10]);
try
    jLocalHost = java.net.InetAddress.getLocalHost();
    fwrite(fid, ['Host: ' char(jLocalHost.getHostName()) ' / ' char(jLocalHost.getHostAddress()) ' (' char(java.lang.System.getProperty('os.name')) ' ' char(java.lang.System.getProperty('os.version')) ')' 10]);
catch
    fwrite(fid, ['Host: Unknown (' char(java.lang.System.getProperty('os.name')) ' ' char(java.lang.System.getProperty('os.version')) ')' 10]);
end


%% ===== SET TEMPORARY FOLDER =====
% Get temp folder
TmpDir = bst_get('BrainstormTmpDir');
% If folder is not defined yet: ask user to set it
if ~isempty(strfind(TmpDir, '/home/bic/'))
    % Hide splash screen
    bst_splash('hide');
    % Display message: first startup
    java_dialog('msgbox', [...
        'Warning: You should change the temporary directory.' 10 10 ...
        'The temporary folder used by Brainstorm is set by default to:' 10 '    ' TmpDir 10 ...
        'You only have 1Gb of available space in the folder /home/bic/, ' 10 ...
        'this is might not be enough for Brainstorm to work properly.' 10 10 ...
        'Please create a folder "brainstorm_tmp" on your local hard drive:' 10 ...
        '    /export01/data/username/brainstorm_tmp or ' 10 ...
        '    /export02/username/brainstorm_tmp', 10 10 ...
        'Then change the temporary directory in the next window.' 10 ], ...
       'BIC workstation: Incorrect temporary folder');
    % Edit preferences
    gui_show('panel_options', 'JavaWindow', 'Brainstorm preferences', [], 1, 0, 0);
end


%% ===== PREPARE BUG REPORTING =====
% % Get current configuration
% BugReportOptions = bst_get('BugReportOptions');
% % If incomplete: ask user to complete it
% if BugReportOptions.isEnabled && (isempty(BugReportOptions.SmtpServer) || isempty(BugReportOptions.UserEmail))
%     gui_show_dialog('Bug reporting', @panel_bug);
% end


%% ===== COMPILED MODE: WAIT =====
if ~isMatlabRunning
    %     % Loop to wait for the end
    %     while brainstorm('status')
    %         pause(2);
    %     end
    %     % Exit Matlab
    %     quit force;

    % Wait until the main Brainstorm mutex gets deleted
    waitfor(bst_mutex('get', 'Brainstorm'));
end



