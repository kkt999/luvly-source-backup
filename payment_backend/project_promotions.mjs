import {validateCampaign,promotionQuote} from './promotions.mjs';

// University-project offers explicitly requested on 16 October 2026 (Malaysia).
// No new-customer claim: eligibility is once per customer, not first purchase.
export const projectOffers=[
  {packageId:'bridal-essentials',name:'Bridal Essentials',basePriceCents:89900,value:5000,code:'ESSENTIAL50',title:'Bridal Essentials · A Beautiful Beginning'},
  {packageId:'signature-bridal',name:'Signature Bridal',basePriceCents:179900,value:10000,code:'SIGNATURE100',title:'Signature Bridal · Your Signature Moment'},
  {packageId:'luxe-bridal',name:'Luxe Bridal',basePriceCents:299900,value:15000,code:'LUXE150',title:'Luxe Bridal · A Little More Luxury'},
].map(p=>({expectedPackageName:p.name,expectedPackagePrice:p.basePriceCents,campaign:{
  id:`project-oct2026-${p.packageId}`,revision:0,kind:'Offer',title:p.title,
  description:`Enjoy RM${p.value/100} off ${p.name} when your package total reaches RM${p.basePriceCents/100}. Apply ${p.code} in My packages before the deposit invoice is issued.`,
  code:p.code,discountType:'Fixed',value:p.value,maxDiscountCents:0,minimumCents:p.basePriceCents,
  packageId:p.packageId,startDate:'2026-10-16',endDate:'2026-11-15',active:true,banner:true,
}}));

export async function createProjectOffers(store,{apply=false,now=Date.now()}={}){
  return store.atomic(async tx=>{
    const pending=[],result=[];
    for(const {campaign,expectedPackageName,expectedPackagePrice} of projectOffers){
      validateCampaign(campaign);
      const p=await tx.get(`servicePackages/${campaign.packageId}`);
      const old=await tx.get(`campaigns/${campaign.id}`);
      const binding=await tx.get(`promotionCodes/${campaign.code}`);
      if(!p?.active||p.name!==expectedPackageName||p.basePriceCents!==expectedPackagePrice||!p.includedGownCount)throw Error('PACKAGE_CHANGED_NO_WRITES');
      if(old){
        // Never reset a manager edit, a deleted campaign, usage, or dates on rerun.
        if(old.deleted||!binding||binding.id!==campaign.id||Object.keys(campaign).some(k=>k!=='revision'&&old[k]!==campaign[k]))throw Error('EXISTING_CAMPAIGN_CHANGED_NO_WRITES');
      }else{
        if(binding)throw Error('CODE_ALREADY_ASSIGNED_NO_WRITES');
        pending.push(campaign);
      }
      const quote=promotionQuote(campaign,p.id??campaign.packageId,p.basePriceCents,now);
      result.push({code:campaign.code,package:p.name,minimumCents:campaign.minimumCents,discountCents:quote.discountCents,standardTotalCents:quote.totalCents,startDate:campaign.startDate,endDate:campaign.endDate,action:old?'Already exists':apply?'Created':'Would create'});
    }
    if(apply){
      for(const campaign of pending){
        tx.set(`campaigns/${campaign.id}`,{...campaign,revision:1,createdAt:now,updatedAt:now,createdBy:'user-requested-project-setup',updatedBy:'user-requested-project-setup'});
        tx.set(`promotionCodes/${campaign.code}`,{id:campaign.id});
      }
    }
    return result;
  });
}
