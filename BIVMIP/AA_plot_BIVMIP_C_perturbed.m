clc
clear all
close all

clim_Hi  = [0,3000];
clim_phi = [0,7];

cmap_phi = parula(256);
cmap_Hi  = itmap(16);

%% Read data
foldernames = {...
  'BIVMIP_C_perfect_5km',...
  'BIVMIP_C_inv_5km_perfect',...
  'BIVMIP_C_inv_5km_visc_hi',...
  'BIVMIP_C_inv_5km_visc_lo',...
  'BIVMIP_C_inv_5km_SMB_hi',...
  'BIVMIP_C_inv_5km_SMB_lo'};

ice_density      = 910;
seawater_density = 1028;

for fi = 1: length(foldernames)
  
  filename_restart       = [foldernames{fi} '/restart_ANT.nc'];
  filename_help_fields   = [foldernames{fi} '/help_fields_ANT.nc'];
  
  results(fi).x          = ncread(filename_restart    ,'x');
  results(fi).y          = ncread(filename_restart    ,'y');
  results(fi).time       = ncread(filename_restart    ,'time');
  ti = length(results(fi).time);
  
  results(fi).Hi         = ncread(filename_restart    ,'Hi'      ,[1,1,ti],[Inf,Inf,1]);
  results(fi).Hb         = ncread(filename_restart    ,'Hb'      ,[1,1,ti],[Inf,Inf,1]);
  results(fi).Hs         = ncread(filename_restart    ,'Hs'      ,[1,1,ti],[Inf,Inf,1]);
  results(fi).phi_fric   = ncread(filename_help_fields,'phi_fric',[1,1,ti],[Inf,Inf,1]);
  
  results(fi).TAF = results(fi).Hi - max(0, (0 - results(fi).Hb) * (seawater_density / ice_density));
end

%% Set up GUI
wa = 500;
ha = 120;

margins_hor = [45,25,125];
margins_ver = [25,25,25,25,25,25,50];

nax = length(margins_hor)-1;
nay = length(margins_ver)-1;

wf = sum(margins_hor) + nax * wa;
hf = sum(margins_ver) + nay * ha;

xlim = [-400,400] * 1e3;
ylim = [-40,40] * 1e3;

H.Fig = figure('position',[200,20,wf,hf],'color','w');
H.Ax  = zeros( nay,nax);
H.Axa = zeros( nay,nax);
for i = 1: nay
  for j = 1: nax
    x = sum(margins_hor(1:j )) + (j -1)*wa;
    ip = nay+1-i;
    y = sum(margins_ver(1:ip)) + (ip-1)*ha;
    H.Ax( i,j) = axes('parent',H.Fig,'units','pixels','position',[x,y,wa,ha],...
      'fontsize',24,'xlim',xlim,'xtick',[],'ylim',ylim,'ytick',[]);
    if (i==1)
      set(H.Ax(i,j),'xaxislocation','top')
    end
  end
end

xlabel(H.Ax(1,1),['Till friction angle (' char(176) ')']);
xlabel(H.Ax(1,2),'Ice thickness (m)');

ylabel(H.Ax(1,1),'Analytical');
ylabel(H.Ax(2,1),'Perfect');
ylabel(H.Ax(3,1),'Visc hi');
ylabel(H.Ax(4,1),'Visc lo');
ylabel(H.Ax(5,1),'SMB hi');
ylabel(H.Ax(6,1),'SMB lo');

% Colormaps
for i = 1:nay
  set(H.Ax(i,1),'clim',clim_phi);
  colormap(H.Ax(i,1),cmap_phi);
  set(H.Ax(i,2),'clim',clim_Hi);
  colormap(H.Ax(i,2),cmap_Hi);
end

% Colorbars
pos = zeros( nay,4);
for i = 1:nay
  pos( i,:) = get(H.Ax(i,2),'pos');
end

% Phi colormap
xmin = pos( 1,1) + pos( 1,3)+15;
ymin = pos( 3,2);
ymax = pos( 1,2) + pos( 1,4);
w = 120;
h = ymax - ymin;
H.Cbarax1 = axes('parent',H.Fig,'units','pixels','position',[xmin,ymin,w,h],'fontsize',24,...
  'xtick',[],'ytick',[]);
H.Cbarax1.XAxis.Visible = 'off';
H.Cbarax1.YAxis.Visible = 'off';
colormap(H.Cbarax1,cmap_phi)
set(H.Cbarax1,'clim',clim_phi);
H.Cbar1 = colorbar(H.Cbarax1,'location','west');
ylabel(H.Cbar1,['Till friction angle (' char(176) ')']);

% Hs colormap
xmin = pos( 1,1) + pos( 1,3)+15;
ymin = pos( 6,2);
ymax = pos( 4,2) + pos( 1,4);
w = 120;
h = ymax - ymin;
H.Cbarax2 = axes('parent',H.Fig,'units','pixels','position',[xmin,ymin,w,h],'fontsize',24,...
  'xtick',[],'ytick',[]);
H.Cbarax2.XAxis.Visible = 'off';
H.Cbarax2.YAxis.Visible = 'off';
colormap(H.Cbarax2,cmap_Hi)
set(H.Cbarax2,'clim',clim_Hi);
H.Cbar2 = colorbar(H.Cbarax2,'location','west');
ylabel(H.Cbar2,'Ice thickness (m)');

%% Plot data
for i = 1:length(foldernames)
  
  image('parent',H.Ax(i,1),'xdata',results(i).x,'ydata',results(i).y,'cdata',results(i).phi_fric','cdatamapping','scaled');
  image('parent',H.Ax(i,2),'xdata',results(i).x,'ydata',results(i).y,'cdata',results(i).Hi','cdatamapping','scaled');
end

% Grounding lines
for fi = 1:length(foldernames)
  
  x_GL = zeros(size(results(fi).y));
  for j = 1:length(results(fi).y)
    i = 1;
    while results(fi).TAF(i)>0; i=i+1; end
    TAF1 = results(fi).TAF(i-1,j);
    TAF2 = results(fi).TAF(i,j);
    lambda = TAF1 / (TAF1 - TAF2);
    x_GL(j) = (1 - lambda) * results(fi).x(i-1) + lambda * results(fi).x(i);
  end
  
  % Mark floating area as uncertain
  if (fi > 1)
    xr = zeros(size(x_GL)) + max(results(1).x);
    xdata = [x_GL; xr];
    ydata = [results(fi).y; flipud(results(fi).y)];
    patch('parent',H.Ax(fi,1),'xdata',xdata,'ydata',ydata,'facecolor','w','edgecolor','none');
  end

  line('parent',H.Ax(fi,1),'xdata',x_GL,'ydata',results(fi).y,'linestyle','-','linewidth',2,'color','k');
  line('parent',H.Ax(fi,2),'xdata',x_GL,'ydata',results(fi).y,'linestyle','-','linewidth',2,'color','k');
end