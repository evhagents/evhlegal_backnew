import React, { useEffect, useRef } from 'react';
import * as echarts from 'echarts';

/** X axis: months */
const months = [
  'Jan','Feb','Mar','Apr','May','Jun',
  'Jul','Aug','Sep','Oct','Nov','Dec'
];

/** Y axis: entities */
const entities = ['EVH Corp', 'EVH LLC'];

/** Buckets: 0=cold, 1=non-urgent, 2=urgent, 3=critical(red-hot) */
const STATUS = { NONE: 0, NON_URGENT: 1, URGENT: 2, CRITICAL: 3 };

/** Business rules for this example */
const rules = {
  'EVH Corp':  { nonUrgentPerMonth: 5, urgentPerMonth: 1 }, // monthly: 5 low + 1 urgent
  'EVH LLC':   { criticalPerMonth: 1 },                      // monthly: taxes (red-hot)
};

/** Map an entity to its monthly status bucket */
const statusFor = (entity) => {
  if (entity === 'EVH LLC' && rules['EVH LLC'].criticalPerMonth > 0) return STATUS.CRITICAL;
  if (entity === 'EVH Corp' && rules['EVH Corp'].urgentPerMonth > 0) return STATUS.URGENT;
  if (entity === 'EVH Corp' && rules['EVH Corp'].nonUrgentPerMonth > 0) return STATUS.NON_URGENT;
  return STATUS.NONE;
};

/** Get status label */
const getStatusLabel = (status) => {
  switch (status) {
    case STATUS.NONE: return 'None';
    case STATUS.NON_URGENT: return 'Non-urgent';
    case STATUS.URGENT: return 'Urgent';
    case STATUS.CRITICAL: return 'Critical';
    default: return 'Unknown';
  }
};

/** Generate heatmap data for ECharts */
const generateHeatmapData = () => {
  const data = [];
  for (let monthIdx = 0; monthIdx < months.length; monthIdx++) {
    for (let entityIdx = 0; entityIdx < entities.length; entityIdx++) {
      const entity = entities[entityIdx];
      const month = months[monthIdx];
      const status = statusFor(entity);
      
      data.push([monthIdx, entityIdx, status, {
        entity,
        month,
        status: getStatusLabel(status)
      }]);
    }
  }
  return data;
};

export default function EntityCalendarHeatmap({ compact = false }) {
  const chartRef = useRef(null);
  const chartInstanceRef = useRef(null);

  useEffect(() => {
    console.log('EntityCalendarHeatmap component rendering with ECharts', { compact });
    
    if (!chartRef.current) {
      console.log('Chart ref not available');
      return;
    }

    // Initialize ECharts instance
    const chartInstance = echarts.init(chartRef.current);
    chartInstanceRef.current = chartInstance;

    // Generate data
    const heatmapData = generateHeatmapData();
    console.log('ECharts heatmap data:', heatmapData);

    // ECharts configuration
    const option = {
      title: {
        text: compact ? '' : 'Entity Activity Heatmap',
        left: 'center',
        textStyle: {
          color: '#10b981',
          fontSize: 16,
          fontWeight: 'bold'
        }
      },
      tooltip: {
        position: 'top',
        formatter: function (params) {
          const data = params.data;
          const customData = data[3];
          return `
            <div style="padding: 8px;">
              <strong>${customData.entity}</strong><br/>
              <strong>${customData.month}</strong><br/>
              Status: <span style="color: ${getStatusColor(data[2])}">${customData.status}</span>
            </div>
          `;
        },
        backgroundColor: 'rgba(0, 0, 0, 0.8)',
        borderColor: '#10b981',
        borderWidth: 1,
        textStyle: {
          color: '#fff'
        }
      },
      grid: {
        height: compact ? '60%' : '70%',
        top: compact ? '10%' : '15%',
        left: '10%',
        right: '10%',
        bottom: '15%'
      },
      xAxis: {
        type: 'category',
        data: months,
        splitArea: {
          show: true
        },
        axisLabel: {
          color: '#9ca3af',
          fontSize: compact ? 10 : 12
        },
        axisLine: {
          lineStyle: {
            color: '#374151'
          }
        }
      },
      yAxis: {
        type: 'category',
        data: entities,
        splitArea: {
          show: true
        },
        axisLabel: {
          color: '#9ca3af',
          fontSize: compact ? 10 : 12
        },
        axisLine: {
          lineStyle: {
            color: '#374151'
          }
        }
      },
      visualMap: {
        min: 0,
        max: 3,
        calculable: true,
        orient: 'horizontal',
        left: 'center',
        bottom: '5%',
        itemWidth: compact ? 15 : 20,
        itemHeight: compact ? 15 : 20,
        textStyle: {
          color: '#9ca3af',
          fontSize: compact ? 10 : 12
        },
        pieces: [
          { min: 0, max: 0, color: 'rgba(255,255,255,0.1)', label: 'None' },
          { min: 1, max: 1, color: '#34d399', label: 'Non-urgent' },
          { min: 2, max: 2, color: '#f59e0b', label: 'Urgent' },
          { min: 3, max: 3, color: '#ef4444', label: 'Critical' }
        ]
      },
      series: [{
        name: 'Entity Activity',
        type: 'heatmap',
        data: heatmapData,
        label: {
          show: false
        },
        emphasis: {
          itemStyle: {
            shadowBlur: 10,
            shadowColor: 'rgba(0, 0, 0, 0.5)'
          }
        }
      }]
    };

    // Set the configuration and render
    chartInstance.setOption(option);

    // Handle window resize with throttling for better performance
    let resizeTimeout;
    const handleResize = () => {
      clearTimeout(resizeTimeout);
      resizeTimeout = setTimeout(() => {
        chartInstance.resize();
      }, 100); // Throttle resize events
    };

    window.addEventListener('resize', handleResize);

    // Cleanup function
    return () => {
      window.removeEventListener('resize', handleResize);
      if (chartInstance) {
        chartInstance.dispose();
      }
    };
  }, [compact]);

  // Helper function to get color for status (for tooltip)
  const getStatusColor = (status) => {
    switch (status) {
      case STATUS.NONE: return 'rgba(255,255,255,0.1)';
      case STATUS.NON_URGENT: return '#34d399';
      case STATUS.URGENT: return '#f59e0b';
      case STATUS.CRITICAL: return '#ef4444';
      default: return 'rgba(255,255,255,0.1)';
    }
  };

  return (
    <div className="w-full">
      <div className={`bg-base-100 rounded-lg shadow-lg ${compact ? 'p-4' : 'p-6'}`}>
        <div 
          ref={chartRef} 
          className={`w-full ${compact ? 'h-64' : 'h-96'}`}
          style={{ minHeight: compact ? '256px' : '384px' }}
        />
      </div>
    </div>
  );
}