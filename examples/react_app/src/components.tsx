import {
  useFormName,
  useIsQueryLoading,
  useStateField,
  useTriggerAction,
  type ComponentRenderer,
} from "@openuidev/react-lang";

type Props = Record<string, any>;
type Element = { props: Props };

const list = (value: unknown): any[] => (Array.isArray(value) ? value : []);

const Stack: ComponentRenderer<Props> = ({ props, renderNode }) => (
  <div className={props.direction === "row" ? "stack row" : "stack"}>{renderNode(props.children)}</div>
);

const Card: ComponentRenderer<Props> = ({ props, renderNode }) => (
  <section className="card">
    <h3>{props.title}</h3>
    {renderNode(props.children)}
  </section>
);

const Text: ComponentRenderer<Props> = ({ props }) =>
  props.variant === "heading" ? <h2>{props.text}</h2> : <p>{props.text}</p>;

const Metric: ComponentRenderer<Props> = ({ props }) => {
  const loading = useIsQueryLoading();
  return (
    <div className={loading ? "metric loading" : "metric"}>
      <strong>{props.value}</strong>
      <span>{props.label}</span>
      {props.trend && (
        <small>
          {props.trend.direction === "up" ? "Up" : "Down"} {props.trend.percent}%
        </small>
      )}
    </div>
  );
};

// The chart reads its Series children directly instead of rendering them.
const LineChart: ComponentRenderer<Props> = ({ props }) => {
  const labels = list(props.labels);
  const series = list(props.series) as Element[];
  const values = series.flatMap((s) => list(s.props.values)).filter((v) => typeof v === "number");
  const highest = Math.max(1, ...values);
  const x = (i: number) => (labels.length > 1 ? (i / (labels.length - 1)) * 300 : 150);
  const y = (v: number) => 110 - (v / highest) * 100;

  return (
    <figure className="chart">
      <svg viewBox="0 0 300 120" preserveAspectRatio="none" role="img">
        {series.map((s, index) => (
          <polyline
            key={index}
            className={`line line-${index % 3}`}
            points={list(s.props.values)
              .map((v, i) => `${x(i)},${y(Number(v) || 0)}`)
              .join(" ")}
          />
        ))}
      </svg>
      <figcaption>
        {labels.join(" · ")}
        {series.map((s, index) => (
          <span key={index} className={`legend line-${index % 3}`}>
            {s.props.name}
          </span>
        ))}
      </figcaption>
    </figure>
  );
};

const Series: ComponentRenderer<Props> = ({ props }) => <span>{props.name}</span>;

// The table reads its Col children directly so rows line up.
const Table: ComponentRenderer<Props> = ({ props }) => {
  const columns = list(props.columns) as Element[];
  const rows = Math.max(0, ...columns.map((c) => list(c.props.data).length));
  const cell = (value: unknown) => (typeof value === "object" && value !== null ? JSON.stringify(value) : String(value ?? ""));

  return (
    <table>
      <thead>
        <tr>
          {columns.map((c, i) => (
            <th key={i}>{c.props.label}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {Array.from({ length: rows }, (_, row) => (
          <tr key={row}>
            {columns.map((c, i) => (
              <td key={i}>{cell(list(c.props.data)[row])}</td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
};

const Col: ComponentRenderer<Props> = ({ props }) => <span>{props.label}</span>;

const Button: ComponentRenderer<Props> = ({ props }) => {
  const trigger = useTriggerAction();
  const formName = useFormName();
  return (
    <span className="buttons">
      <button
        type="button"
        className={props.variant === "primary" ? "primary" : undefined}
        onClick={() => trigger(props.label, formName, props.action)}
      >
        {props.label}
      </button>
      {props.share && (
        <button type="button" onClick={() => trigger(props.label, formName, props.share)}>
          Share
        </button>
      )}
    </span>
  );
};

const Form: ComponentRenderer<Props> = ({ props, renderNode }) => (
  <fieldset className="form">{renderNode(props.children)}</fieldset>
);

const Input: ComponentRenderer<Props> = ({ props }) => {
  const field = useStateField(props.name, props.value);
  return (
    <input
      placeholder={props.placeholder}
      value={String(field.value ?? "")}
      onChange={(event) => field.setValue(event.target.value)}
    />
  );
};

const Select: ComponentRenderer<Props> = ({ props, renderNode }) => {
  const field = useStateField(props.name, props.value);
  return (
    <select value={String(field.value ?? "")} onChange={(event) => field.setValue(event.target.value)}>
      <option value="" />
      {renderNode(props.items)}
    </select>
  );
};

const SelectItem: ComponentRenderer<Props> = ({ props }) => <option value={props.value}>{props.label}</option>;

const Highlight: ComponentRenderer<Props> = ({ props, renderNode }) => (
  <aside className={props.enabled === false ? undefined : "highlight"}>{renderNode(props.content)}</aside>
);

export const renderers = {
  Stack,
  Card,
  Text,
  Metric,
  LineChart,
  Series,
  Table,
  Col,
  Button,
  Form,
  Input,
  Select,
  SelectItem,
  Highlight,
};
