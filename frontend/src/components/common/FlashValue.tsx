import React, { useEffect, useState, useRef } from 'react';

interface FlashValueProps extends React.HTMLAttributes<HTMLSpanElement> {
  value: any;
  children?: React.ReactNode;
}

export const FlashValue: React.FC<FlashValueProps> = ({ value, children, className = '', ...props }) => {
  const [isFlashing, setIsFlashing] = useState(false);
  const prevValue = useRef(value);

  useEffect(() => {
    if (value !== prevValue.current) {
      setIsFlashing(true);
      const timer = setTimeout(() => setIsFlashing(false), 800);
      prevValue.current = value;
      return () => clearTimeout(timer);
    }
  }, [value]);

  return (
    <span {...props} className={`${className} ${isFlashing ? 'pop' : ''}`}>
      {children || value}
    </span>
  );
};
