function bmiCategory(b){if(b<18.5)return'Underweight';if(b<25)return'Normal';if(b<30)return'Overweight';return'Obese';}
function calculateMetrics({weightKg,heightCm,age,sex,activity}){
 const h=heightCm/100;const bmi=+(weightKg/(h*h)).toFixed(1);
 let bmr=sex==='male'?10*weightKg+6.25*heightCm-5*age+5:10*weightKg+6.25*heightCm-5*age-161;
 const mult={sedentary:1.2,light:1.375,moderate:1.55,active:1.725,very_active:1.9}[activity]||1.2;
 return {bmi,bmiCategory:bmiCategory(bmi),bmr:Math.round(bmr),dailyCalories:Math.round(bmr*mult)};
}
module.exports={calculateMetrics};