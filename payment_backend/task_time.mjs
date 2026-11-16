// Full-hour MYT work blocks share the same transactional day record as visits.
export const taskBusy=(day,uid,hour,excluding)=>Object.entries(day?.taskBlocks??{}).some(([id,t])=>id!==excluding&&t.staffId===uid&&hour<t.endHour&&hour+1>t.startHour);
export const taskQualified=(profile,type)=>type==='Other'||({'Fitting preparation':['FittingSpecialist','Consultant'],'Alteration':['FittingSpecialist'],'Bridal makeup':['MakeupArtist'],'Front desk':['FrontDesk']}[type]??[]).includes(profile?.jobRole);
