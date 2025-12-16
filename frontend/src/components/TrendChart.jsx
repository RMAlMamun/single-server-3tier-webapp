import React,{useEffect,useState}from'react';import{Line}from'react-chartjs-2';
import api from'../api';import{Chart as C,CategoryScale,LinearScale,PointElement,LineElement,Title,Tooltip,Legend}from'chart.js';
C.register(CategoryScale,LinearScale,PointElement,LineElement,Title,Tooltip,Legend);

export default function TC(){
  const[d,sd]=useState(null);
  const[loading,setLoading]=useState(true);
  const[error,setError]=useState(null);
  
  useEffect(()=>{
    setLoading(true);
    api.get('/measurements/trends')
      .then(r=>{
        console.log('Trend data:', r.data);
        const rows=r.data.rows;
        if(rows && rows.length > 0){
          sd({
            labels:rows.map(x=>new Date(x.day).toLocaleDateString()),
            datasets:[{
              label:'Average BMI',
              data:rows.map(x=>parseFloat(x.avg_bmi)),
              borderColor:'rgb(75, 192, 192)',
              backgroundColor:'rgba(75, 192, 192, 0.2)',
              tension:0.1
            }]
          });
        } else {
          setError(null); // Clear error if no data
        }
      })
      .catch(err=>{
        console.error('Failed to load trends:',err);
        console.error('Error details:', err.response?.data);
        setError('Failed to load trend data');
      })
      .finally(()=>setLoading(false));
  },[]);
  
  if(loading) return <div className="loading">Loading chart</div>;
  if(error) return <div className="alert alert-error">{error}</div>;
  if(!d) return <div className="empty-state"><p>No trend data available yet. Add measurements over multiple days to see trends!</p></div>;
  
  return <Line data={d} options={{
    responsive:true,
    plugins:{
      legend:{position:'top'},
      title:{display:true,text:'30-Day BMI Trend'}
    }
  }}/>;
}