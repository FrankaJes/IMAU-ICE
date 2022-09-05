clc
clear all
close all

do_set_PD_to_zero = true;
do_remove_jumps   = true;
plotas            = 'plume';
% plotas            = 'lines';

scenarios = {...
  'ctrl',...
  'rcp26',...
  'ssp126',...
  'rcp85',...
  'ssp585'};

foldernames_histor = {...
  '../spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_40km',...
  '../spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_30km',...
  '../spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_20km',...
  '../spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_16km',...
  '../spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_PMIP3ens_10km',...
  '../spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_HadCM3_20km',...
  '../spinup_GRL/phase5_historicalperiod/hybrid_ZoetIverson_CCSM_20km',...
  '../spinup_GRL/phase5_historicalperiod/hybrid_Coulombreg_PMIP3ens_20km'};

%% Read historical period
for fi = 1: length( foldernames_histor)
  filename = [foldernames_histor{ fi} '/scalar_output_global.nc'];
  histor( fi).time = ncread( filename,'time') + 1950;
  histor( fi).GMSL = ncread( filename,'GMSL_GRL');
  % fix the first-timestep-bump (why is it there?!)
  histor( fi).GMSL(1) = histor( fi).GMSL(2) - (histor( fi).GMSL(3) - histor( fi).GMSL(2));
  if do_set_PD_to_zero
    histor( fi).GMSL = histor( fi).GMSL - histor( fi).GMSL( end);
  end
end

%% Calculate plume for historical period
  
plume_histor.time     = histor( 1).time;
plume_histor.GMSL_av  = zeros( size( histor( 1).time));
plume_histor.GMSL_min = zeros( size( histor( 1).time)) + Inf;
plume_histor.GMSL_max = zeros( size( histor( 1).time)) - Inf;
plume_histor.nsims    = 0;

for fi = 1: length( histor)
  plume_histor.nsims    =      plume_histor.nsims + 1;
  plume_histor.GMSL_min = min( plume_histor.GMSL_min, histor( fi).GMSL);
  plume_histor.GMSL_max = max( plume_histor.GMSL_max, histor( fi).GMSL);
  plume_histor.GMSL_av  =      plume_histor.GMSL_av + histor( fi).GMSL;
end

plume_histor.GMSL_av = plume_histor.GMSL_av / plume_histor.nsims;

%% Read future projections
henk = dir;
fi = 0;
for i = 1: length( henk)
  if henk( i).isdir && startsWith( henk( i).name,'IMAUICE') %&& isempty( strfind( henk( i).name,'IMAUICE4'))
    filename = [henk( i).name '/scalar_output_global.nc'];
    fi = fi+1;
    future( fi).name = henk( i).name;
    future( fi).time = ncread( filename,'time');
    future( fi).GMSL = ncread( filename,'GMSL_GRL');
    % fix the first-timestep-bump (why is it there?!)
    if do_remove_jumps
      future( fi).GMSL(1) = future( fi).GMSL(2) - (future( fi).GMSL(3) - future( fi).GMSL(2));
    end
    % define 2014 as 0
    if do_set_PD_to_zero
      future( fi).GMSL = future( fi).GMSL - future( fi).GMSL( 1);
    end
  end
end

%% Calculate plumes for scenarios
for sci = 1: length( scenarios)
  
  plume( sci).name     = scenarios{ sci};
  plume( sci).time     = future( 1).time;
  plume( sci).GMSL_av  = zeros( size( future( 1).time));
  plume( sci).GMSL_min = zeros( size( future( 1).time)) + Inf;
  plume( sci).GMSL_max = zeros( size( future( 1).time)) - Inf;
  plume( sci).nsims    = 0;
  
  for fi = 1: length( future)
    if ~isempty( strfind( future( fi).name, scenarios{ sci}))
      plume( sci).nsims    =      plume( sci).nsims + 1;
      plume( sci).GMSL_min = min( plume( sci).GMSL_min, future( fi).GMSL);
      plume( sci).GMSL_max = max( plume( sci).GMSL_max, future( fi).GMSL);
      plume( sci).GMSL_av  =      plume( sci).GMSL_av + future( fi).GMSL;
    end
  end
  
  plume( sci).GMSL_av = plume( sci).GMSL_av / plume( sci).nsims;
  
end

%% Set up GUI
wa1 = 800;
ha  = 500;
wa2 = 70;

margin_left   = 80;
margin_mid    = 25;
margin_right  = 85;
margin_bottom = 85;
margin_top    = 50;

wf = margin_left   + wa1 + margin_mid + wa2 + margin_right;
hf = margin_bottom + ha + margin_top;

xlim  = [1960,2100];
ylim  = [-2,22];
ytick = -2:2:22;

H.Fig = figure('position',[200,200,wf,hf],'color','w');
H.Ax1  = axes('parent',H.Fig,'units','pixels','position',[margin_left,margin_bottom,wa1,ha],'fontsize',24,...
  'xgrid','on','ygrid','on','xlim',xlim,'ylim',ylim,'ytick',ytick);

xlabel(H.Ax1,'Time (yr CE)')
ylabel(H.Ax1,'Sea level contribution (cm)')

% Empty objects for legend
colors = [0,0,0; linspecer( length( scenarios)-1,'sequential')];
for sci = 1: length( scenarios)
  patch('parent',H.Ax1,'xdata',[],'ydata',[],'facecolor',colors( sci,:),'edgecolor',colors( sci,:),'facealpha',0.5,'linewidth',2);
end

% Second axes for bars
H.Ax2 = axes('parent',H.Fig,'units','pixels','position',[margin_left+wa1+margin_mid,margin_bottom,wa2,ha],...
  'xlim',[-0.2,length(scenarios)+0.2],'ylim',ylim,'fontsize',24,'yaxislocation','right','ygrid','on','ytick',ytick);
H.Ax2.XAxis.Visible = 'off';
ylabel(H.Ax2,'Sea level contribution in 2100 (cm)')

%% Plot historical period
if strcmpi( plotas,'plume')
  xdata = [plume_histor.time    ; flipud( plume_histor.time    )];
  ydata = [plume_histor.GMSL_min; flipud( plume_histor.GMSL_max)] * 100; % Because cm instead of m
  patch('parent',H.Ax1,'xdata',xdata,'ydata',ydata,'facecolor','k','edgecolor','none','facealpha',0.5);
  line( 'parent',H.Ax1,'xdata',plume_histor.time,'ydata',plume_histor.GMSL_min * 100,'color','k','linewidth',2);
  line( 'parent',H.Ax1,'xdata',plume_histor.time,'ydata',plume_histor.GMSL_max * 100,'color','k','linewidth',2);
  line( 'parent',H.Ax1,'xdata',plume_histor.time,'ydata',plume_histor.GMSL_av  * 100,'color','k','linewidth',3);
elseif strcmpi( plotas,'lines')
  for hi = 1: length( histor)
    line('parent',H.Ax1,'xdata',histor( hi).time,'ydata',histor( hi).GMSL*100,'color','k','linewidth',1);
  end
else
  error(['unknown plotas "' plotas '"'])
end

%% Plot projections
if strcmpi( plotas,'plume')
  for sci = length( scenarios): -1: 1
    xdata = [plume( sci).time    ; flipud( plume( sci).time    )];
    ydata = [plume( sci).GMSL_min; flipud( plume( sci).GMSL_max)] * 100; % Because cm instead of m
    patch('parent',H.Ax1,'xdata',xdata,'ydata',ydata,'facecolor',colors( sci,:),'edgecolor','none','facealpha',0.3);
    line( 'parent',H.Ax1,'xdata',plume( sci).time,'ydata',plume( sci).GMSL_min * 100,'color',colors( sci,:),'linewidth',2);
    line( 'parent',H.Ax1,'xdata',plume( sci).time,'ydata',plume( sci).GMSL_max * 100,'color',colors( sci,:),'linewidth',2);
    line( 'parent',H.Ax1,'xdata',plume( sci).time,'ydata',plume( sci).GMSL_av  * 100,'color',colors( sci,:),'linewidth',3);
  end
elseif strcmpi( plotas,'lines')
  for sci = 1: length( scenarios)
    for fi = 1: length( future)
      if ~isempty( strfind( future( fi).name, scenarios{ sci}))
        line('parent',H.Ax1,'xdata',future( fi).time,'ydata',future( fi).GMSL*100,'color',colors( sci,:),'linewidth',1);
      end
    end
  end
else
  error(['unknown plotas "' plotas '"'])
end

% Bars
wb = 0.8;
for sci = 1: length( scenarios)
  xlo = (sci-1) + (1-wb)/2;
  xhi = xlo + wb;
  y   = plume( sci).GMSL_av(  end);
  ylo = plume( sci).GMSL_min( end);
  yhi = plume( sci).GMSL_max( end);
  xdata = [xlo,xhi,xhi,xlo];
  ydata = [ylo,ylo,yhi,yhi] * 100;
  patch('parent',H.Ax2,'xdata',xdata,'ydata',ydata,'facecolor',colors( sci,:),'edgecolor','none','facealpha',0.5);
  line('parent',H.Ax2,'xdata',[xlo,xhi],'ydata',[y,y]*100,'color',colors( sci,:),'linewidth',3);
end

%% Legend
legend(H.Ax1,scenarios,'location','northwest');