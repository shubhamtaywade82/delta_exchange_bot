import React, { useEffect, useState, useRef } from 'react';

interface FlashValueProps extends React.HTMLAttributes<HTMLSpanElement> {
  value: string | number | null | undefined;
  children?: React.ReactNode;
}

export const FlashValue: React.FC<FlashValueProps> = ({ value, children, className = '', ...props }) => {
  const [isFlashing, setIsFlashing] = useState(false);
  const prevValue = useRef(value);

  useEffect(() => {
    if (value === prevValue.current) return undefined;

    prevValue.current = value;
    const raf = requestAnimationFrame(() => {
      setIsFlashing(true);
      setTimeout(() => setIsFlashing(false), 800);
    });
    return () => cancelAnimationFrame(raf);
  }, [value]);

  return (
    <span {...props} className={`${className} ${isFlashing ? 'pop' : ''}`}>
      {children || value}
    </span>
  );
};
